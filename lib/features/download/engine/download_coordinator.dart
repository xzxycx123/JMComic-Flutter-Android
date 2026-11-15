import 'dart:async';
import 'dart:io';

import 'package:collection/collection.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/utils/logger.dart';
import '../../../data/local/download_store.dart';
import '../../../data/models/download_record.dart';
import '../../../data/sources/jm_api_client.dart';
import 'download_slots.dart';
import 'download_task.dart';
import 'download_worker.dart';
import 'notification_service.dart';
import 'pdf_sink.dart';

/// 入队 / 取消 / 重试 / 清空已完成（移植 `JmScript/download/DownloadCoordinator.kt`）。
class DownloadCoordinator {
  DownloadCoordinator({
    required Future<JmApi> Function() apiLoader,
    required DownloadHistory history,
    required PdfSink sink,
    DownloadNotificationService? notifications,
    DownloadSlots? slots,
    Directory? workRoot,
  })  : _history = history,
        _notifications = notifications,
        _slots = slots ?? DownloadSlots(AppConfig.maxParallelTasks) {
    _worker = DownloadWorker(
      apiLoader: apiLoader,
      history: history,
      sink: sink,
      notifications: notifications,
      workRoot: workRoot,
    );
  }

  final DownloadHistory _history;
  final DownloadNotificationService? _notifications;
  final DownloadSlots _slots;
  final Map<String, CancellationToken> _tokens = <String, CancellationToken>{};
  late final DownloadWorker _worker;

  DownloadHistory get history => _history;

  /// 同 albumId 已有 queued/running 时直接返回既有任务（去重）。
  Future<DownloadRecord> enqueue(String albumId) async {
    final existing = _history.records.firstWhereOrNull(
      (record) => record.albumId == albumId && record.isActive,
    );
    if (existing != null) return existing;

    final now = DateTime.now().millisecondsSinceEpoch;
    final workId = newWorkId();
    final record = DownloadRecord(
      workId: workId,
      albumId: albumId,
      state: DownloadState.queued,
      status: '等待...',
      createdAt: now,
      updatedAt: now,
    );
    await _history.add(record);
    final token = CancellationToken();
    _tokens[workId] = token;
    unawaited(_run(workId, albumId, token));
    return record;
  }

  Future<List<DownloadRecord>> enqueueAll(List<String> albumIds) async {
    final results = <DownloadRecord>[];
    for (final albumId in albumIds) {
      results.add(await enqueue(albumId));
    }
    return results;
  }

  Future<void> cancel(String workId) async {
    final token = _tokens[workId];
    token?.cancel();
    _tokens.remove(workId);
    await _history.update(workId, (record) {
      if (record.isFinished) return record;
      return record.copyWith(
        state: DownloadState.cancelled,
        status: '已取消',
        detail: '临时文件已清理',
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );
    });
    await _stopServiceIfIdle();
  }

  Future<void> retry(String workId) async {
    final record = _history.records.firstWhereOrNull((item) => item.workId == workId);
    if (record == null || record.isActive) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    await _history.update(workId, (item) {
      return item.copyWith(
        state: DownloadState.queued,
        status: '排队等待',
        detail: '',
        done: 0,
        total: 0,
        percent: 0,
        updatedAt: now,
        clearError: true,
        clearPdf: true,
      );
    });

    final token = CancellationToken();
    _tokens[workId] = token;
    unawaited(_run(workId, record.albumId, token));
  }

  Future<void> remove(String workId) async {
    _tokens.remove(workId)?.cancel();
    await _history.remove(workId);
    await _stopServiceIfIdle();
  }

  Future<void> clearFinished() => _history.clearFinished();

  /// 冷启动：把僵尸 running 标成 failed，并允许一键重试。
  Future<int> recoverInterrupted() => _history.markInterrupted();

  Future<void> _run(String workId, String albumId, CancellationToken token) async {
    var attempt = 0;
    await _notifications?.ensureStarted(title: 'JMComic', text: 'JM$albumId 排队中');
    while (true) {
      try {
        // 排队期间已取消：不要再等槽位、更不要起任务。
        token.throwIfCancelled();
        await _slots.withSlot(() => _worker.run(workId, albumId, token));
        _tokens.remove(workId);
        await _stopServiceIfIdle();
        return;
      } on JmCancelledException {
        _tokens.remove(workId);
        await _markCancelled(workId);
        await _stopServiceIfIdle();
        return;
      } on JmContentException catch (error) {
        _tokens.remove(workId);
        await _markFailed(workId, error.message);
        await _stopServiceIfIdle();
        return;
      } catch (error) {
        if (token.isCancelled) {
          _tokens.remove(workId);
          await _markCancelled(workId);
          await _stopServiceIfIdle();
          return;
        }
        final message = _readable(error);
        // 非网络类失败（图片解码失败、URL 拼错、响应结构异常）重试也救不回来。
        final retryable = error is! JmApiException || error.network;
        attempt++;
        if (!retryable || attempt > AppConfig.maxIoRetries) {
          _tokens.remove(workId);
          await _markFailed(workId, message);
          await _stopServiceIfIdle();
          return;
        }
        Log.w('任务 $workId 第 $attempt 次失败，准备重试：$message');
        await _history.update(workId, (record) {
          if (record.state == DownloadState.cancelled) return record;
          return record.copyWith(
            state: DownloadState.queued,
            status: '连接失败，正在自动重试',
            detail: message,
            done: 0,
            total: 0,
            percent: 0,
            updatedAt: DateTime.now().millisecondsSinceEpoch,
          );
        });
        await Future<void>.delayed(Duration(milliseconds: 600 * attempt));
      }
    }
  }

  Future<void> _markCancelled(String workId) {
    return _history.update(workId, (record) {
      if (record.state == DownloadState.cancelled) return record;
      return record.copyWith(
        state: DownloadState.cancelled,
        status: '已取消',
        detail: '临时文件已清理',
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );
    });
  }

  Future<void> _markFailed(String workId, String message) {
    return _history.update(workId, (record) {
      return record.copyWith(
        state: DownloadState.failed,
        status: '下载失败',
        detail: message,
        error: message,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );
    });
  }

  Future<void> _stopServiceIfIdle() async {
    if (_history.records.any((record) => record.isActive)) return;
    _tokens.clear();
    await _notifications?.stop();
  }

  static String _readable(Object error) {
    if (error is JmException) {
      final message = error.message.trim();
      if (message.isNotEmpty) return message.length > 500 ? message.substring(0, 500) : message;
    }
    final text = error.toString().trim();
    return text.isEmpty ? '网络连接失败，请稍后重试' : text;
  }
}
