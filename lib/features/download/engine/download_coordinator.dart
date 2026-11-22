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
import 'reader_export_worker.dart';

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
    _readerWorker = ReaderExportWorker(
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

  /// 阅读器结束页导出的任务参数（含阅读缓存闭包）。
  ///
  /// **只在任务进行中保留**：成功 / 失败 / 取消 / 移除 / 清空都立刻移除，
  /// 避免 reader、loader 与缓存字节被无上限地挂在 coordinator 上。失败后的重试
  /// 用持久化记录里的章节信息重建「纯网络」导出。
  final Map<String, ReaderExportJob> _readerJobs = <String, ReaderExportJob>{};
  late final DownloadWorker _worker;
  late final ReaderExportWorker _readerWorker;

  DownloadHistory get history => _history;

  /// 整本下载去重：只匹配**整本**（`chapterId` 为空）的进行中任务。
  ///
  /// 阅读器结束页的章节导出任务也带同一个 albumId，不能让它把整本下载顶掉。
  Future<DownloadRecord> enqueue(String albumId) async {
    final existing = _history.records.firstWhereOrNull(
      (record) =>
          record.albumId == albumId &&
          record.chapterId.isEmpty &&
          record.isActive,
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

  /// 阅读器结束页的页面级导出：先落一条 queued 记录（下载页立刻可见），再按页合并。
  ///
  /// 去重规则：同一本已有进行中的任务时直接复用——整本任务（`chapterId` 为空）也算，
  /// 因为它已经包含这一章；同一本同一章再点一次也复用，避免重复点出多条任务。
  Future<({DownloadRecord record, bool reused})> enqueueReaderExport(
    ReaderExportJob job,
  ) async {
    final existing = _history.records.firstWhereOrNull(
      (record) =>
          record.isActive &&
          record.albumId == job.albumId &&
          (record.chapterId.isEmpty || record.chapterId == job.chapterId),
    );
    if (existing != null) return (record: existing, reused: true);

    final now = DateTime.now().millisecondsSinceEpoch;
    final workId = newWorkId();
    final record = DownloadRecord(
      workId: workId,
      albumId: job.albumId,
      chapterId: job.chapterId,
      // 原始专辑标题（可能为空）；展示时由 displayTitle 回落 JM 号。
      title: job.albumTitle,
      chapterTitle: job.chapterTitle,
      state: DownloadState.queued,
      status: '等待导出',
      total: job.total,
      createdAt: now,
      updatedAt: now,
    );
    await _history.add(record);
    final token = CancellationToken();
    _tokens[workId] = token;
    _readerJobs[workId] = job;
    unawaited(_runReaderExport(workId, job, token));
    return (record: record, reused: false);
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
    final record =
        _history.records.firstWhereOrNull((item) => item.workId == workId);
    if (record == null || record.isActive) return;
    final isReaderExport = record.chapterId.isNotEmpty;

    final now = DateTime.now().millisecondsSinceEpoch;
    await _history.update(workId, (item) {
      return item.copyWith(
        state: DownloadState.queued,
        status: '排队等待',
        detail: '',
        done: 0,
        // 章节导出的 total 是重建任务的唯一页数依据，不能清零；整本任务由 worker
        // 重新从 /album 取页数，保持原来的清零语义。
        total: isReaderExport ? item.total : 0,
        percent: 0,
        updatedAt: now,
        clearError: true,
        clearPdf: true,
      );
    });

    final token = CancellationToken();
    _tokens[workId] = token;
    // 终态不再保留阅读缓存闭包（避免内存无上限），统一按持久化记录重建：
    // 有 total 时直接按章节页数导出，没有 total 时 worker 会用既有 API 恢复。
    _readerJobs.remove(workId);
    if (isReaderExport) {
      unawaited(
        _runReaderExport(
          workId,
          ReaderExportJob(
            albumId: record.albumId,
            chapterId: record.chapterId,
            albumTitle: record.title,
            chapterTitle: record.chapterTitle,
            total: record.total,
          ),
          token,
        ),
      );
    } else {
      unawaited(_run(workId, record.albumId, token));
    }
  }

  Future<void> remove(String workId) async {
    _tokens.remove(workId)?.cancel();
    _readerJobs.remove(workId);
    await _history.remove(workId);
    await _stopServiceIfIdle();
  }

  Future<void> clearFinished() async {
    for (final record in _history.records.where((item) => item.isFinished)) {
      _readerJobs.remove(record.workId);
    }
    await _history.clearFinished();
  }

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

  /// 阅读器结束页导出：复用队列槽位、取消信号与失败文案，记录仍写在同一个
  /// [DownloadHistory] 里，所以既有下载页能直接看到任务/进度/结果。
  Future<void> _runReaderExport(
    String workId,
    ReaderExportJob job,
    CancellationToken token,
  ) async {
    await _notifications?.ensureStarted(
      title: 'JMComic',
      text: 'JM${job.albumId} 正在导出 PDF',
    );
    try {
      token.throwIfCancelled();
      await _slots.withSlot(() => _readerWorker.run(workId, job, token));
      _tokens.remove(workId);
    } on JmCancelledException {
      _tokens.remove(workId);
      await _markCancelled(workId);
    } on JmContentException catch (error) {
      _tokens.remove(workId);
      await _markFailed(workId, error.message);
    } catch (error) {
      _tokens.remove(workId);
      if (token.isCancelled) {
        await _markCancelled(workId);
      } else {
        await _markFailed(workId, _readable(error));
      }
    } finally {
      // 终态（成功 / 失败 / 取消）一律释放缓存闭包：不把 reader/loader/字节挂在 coordinator 上。
      _readerJobs.remove(workId);
      await _stopServiceIfIdle();
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
