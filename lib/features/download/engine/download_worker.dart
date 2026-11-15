import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../../core/config/app_config.dart';
import '../../../core/image/image_processor.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/utils/file_names.dart';
import '../../../core/utils/logger.dart';
import '../../../data/local/download_store.dart';
import '../../../data/models/download_record.dart';
import '../../../data/sources/jm_api_client.dart';
import 'download_slots.dart';
import 'download_task.dart';
import 'notification_service.dart';
import 'pdf_exporter.dart';
import 'pdf_sink.dart';

/// 单任务流水线（移植 `JmScript/download/JmDownloadWorker.kt`，见 PLAN §8.2）。
class DownloadWorker {
  DownloadWorker({
    required Future<JmApi> Function() apiLoader,
    required DownloadHistory history,
    required PdfSink sink,
    DownloadNotificationService? notifications,
    Directory? workRoot,
  })  : _apiLoader = apiLoader,
        _history = history,
        _sink = sink,
        _notifications = notifications,
        _workRootOverride = workRoot;

  final Future<JmApi> Function() _apiLoader;
  final DownloadHistory _history;
  final PdfSink _sink;
  final DownloadNotificationService? _notifications;
  final Directory? _workRootOverride;

  /// 进度节流状态按 workId 隔离（同一个 worker 会被 3 个并发任务复用）。
  final Map<String, ({String? status, int percent, DateTime at})> _throttle =
      <String, ({String? status, int percent, DateTime at})>{};

  Future<void> run(
    String workId,
    String albumId,
    CancellationToken token,
  ) async {
    // 排队期间被取消时，不要再起线程/建目录/触发 /setting。
    token.throwIfCancelled();
    final root = await _workRoot();
    final workDir = Directory('${root.path}${Platform.pathSeparator}$workId');
    if (workDir.existsSync()) {
      workDir.deleteSync(recursive: true);
    }
    workDir.createSync(recursive: true);

    try {
      await _write(
        workId,
        (record) => record.copyWith(
          state: DownloadState.running,
          status: '等待下载通道',
          detail: '',
          percent: 0,
        ),
      );
      await _notify('JM$albumId', '等待下载通道');

      final api = await _apiLoader();
      token.throwIfCancelled();

      await _report(workId, '正在连接 JM 服务', '自动选择可用线路', 0, 0, force: true);
      final album = await api.getAlbum(albumId);
      token.throwIfCancelled();

      await _write(
        workId,
        (record) => record.copyWith(title: album.title, total: album.totalPages),
      );
      await _notify('JM${album.id}', album.title);

      var expectedTotal = album.totalPages;
      var completed = 0;
      var failedPages = 0;
      final pages = <File>[];

      for (var chapterIndex = 0; chapterIndex < album.chapters.length; chapterIndex++) {
        token.throwIfCancelled();
        final reference = album.chapters[chapterIndex];
        await _report(
          workId,
          '正在获取章节 ${chapterIndex + 1}/${album.chapters.length}',
          reference.displayTitle,
          completed,
          expectedTotal,
          force: true,
        );

        final chapter = await api.getChapter(reference);
        token.throwIfCancelled();
        if (expectedTotal <= 0) expectedTotal = chapter.pageCount;
        final scrambleId = await api.getScrambleId(chapter.id);

        final chapterDir = Directory(
          '${workDir.path}${Platform.pathSeparator}${(chapterIndex + 1).toString().padLeft(4, '0')}',
        )..createSync(recursive: true);

        final chapterIndexBase = chapterIndex;
        final results = await mapWithConcurrency<String, File?>(
          chapter.images,
          AppConfig.maxParallelImages,
          (filename, imageIndex) async {
            token.throwIfCancelled();
            final raw = await api.downloadImage(chapter.id, filename);
            final png = await ImageProcessor.restore(
              RestoreRequest(
                raw: raw,
                scrambleId: scrambleId,
                photoId: int.tryParse(chapter.id) ?? 0,
                filename: filename,
              ),
            );
            if (png == null) {
              throw JmApiException('图片 $filename 解码失败', network: false);
            }
            final target = File(
              '${chapterDir.path}${Platform.pathSeparator}${(imageIndex + 1).toString().padLeft(5, '0')}.png',
            );
            await target.writeAsBytes(png, flush: true);
            completed++;
            await _report(
              workId,
              '正在下载图片 · 章节 ${chapterIndexBase + 1}/${album.chapters.length}',
              '${reference.displayTitle}\n本章 ${imageIndex + 1}/${chapter.images.length} 页',
              completed,
              expectedTotal < completed ? completed : expectedTotal,
            );
            return target;
          },
          onError: (filename, imageIndex, error) {
            failedPages++;
            Log.w('页面 $filename 失败：$error');
            return null;
          },
        );

        final chapterFiles = results.whereType<File>().toList()
          ..sort((a, b) => a.path.compareTo(b.path));
        pages.addAll(chapterFiles);
      }

      token.throwIfCancelled();
      // PLAN §11：失败页达到上限即整任务失败（不允许静默缺页）。
      if (failedPages >= AppConfig.maxFailedPages) {
        throw JmApiException('$failedPages 页下载失败，请稍后重试', network: true);
      }
      if (pages.isEmpty) {
        throw const JmContentException('这本漫画没有可导出的页面');
      }

      await _report(
        workId,
        '正在生成 PDF',
        '已下载 ${pages.length} 页，正在逐页写入 Documents',
        pages.length,
        pages.length,
        force: true,
      );
      await _notify('正在生成 PDF', 'JM${album.id} · ${pages.length} 页');

      final pdfBytes = await PdfExporter.exportFiles(pages);
      token.throwIfCancelled();

      final requested = pdfName(album.id, album.title);
      final exported = await _sink.write(requested, pdfBytes);
      token.throwIfCancelled();

      await _write(
        workId,
        (record) => record.copyWith(
          state: DownloadState.succeeded,
          status: '导出完成',
          title: album.title,
          detail: failedPages > 0 ? '$failedPages 页解码失败' : '',
          done: pages.length,
          total: pages.length,
          percent: 100,
          pageCount: pages.length,
          pdfName: exported.name,
          pdfUri: exported.uri,
          pdfPath: exported.path,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
          clearError: true,
        ),
      );
      await _notify('下载完成', exported.name);
      Log.i('任务 $workId 完成：${exported.name}');
    } finally {
      _throttle.remove(workId);
      // 成功 / 失败 / 取消都清空临时目录（PLAN §8.2 step 10）。
      try {
        if (workDir.existsSync()) workDir.deleteSync(recursive: true);
      } catch (error) {
        Log.w('清理临时目录失败：$error');
      }
    }
  }

  Future<Directory> _workRoot() async {
    final override = _workRootOverride;
    if (override != null) {
      if (!override.existsSync()) override.createSync(recursive: true);
      return override;
    }
    final cache = await getTemporaryDirectory();
    final root = Directory('${cache.path}${Platform.pathSeparator}jm-pdf');
    if (!root.existsSync()) root.createSync(recursive: true);
    return root;
  }

  Future<void> _write(
    String workId,
    DownloadRecord Function(DownloadRecord record) transform,
  ) {
    return _history.update(workId, (record) {
      // 已取消/已结束的记录不允许被流水线回写成 running（取消后 UI 会抖动）。
      if (record.state == DownloadState.cancelled) return record;
      final next = transform(record);
      return next.updatedAt == record.updatedAt
          ? next.copyWith(updatedAt: DateTime.now().millisecondsSinceEpoch)
          : next;
    });
  }

  Future<void> _report(
    String workId,
    String status,
    String detail,
    int done,
    int total, {
    bool force = false,
  }) async {
    final percent = total > 0 ? ((done * 100) ~/ total).clamp(0, 100).toInt() : 0;
    final now = DateTime.now();
    final last = _throttle[workId];
    final changed = last == null || status != last.status || percent != last.percent;
    final elapsed = last == null
        ? const Duration(days: 1)
        : now.difference(last.at);
    if (!force && !changed && elapsed < AppConfig.progressWriteThrottle) return;

    _throttle[workId] = (status: status, percent: percent, at: now);

    await _write(
      workId,
      (record) => record.copyWith(
        state: DownloadState.running,
        status: status,
        detail: detail,
        done: done,
        total: total,
        percent: percent,
        updatedAt: now.millisecondsSinceEpoch,
      ),
    );
    await _notify(status, detail);
  }

  Future<void> _notify(String title, String text) async {
    await _notifications?.update(title: title, text: text.replaceAll('\n', ' · '));
  }
}
