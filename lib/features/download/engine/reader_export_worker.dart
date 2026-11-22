import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import '../../../core/config/app_config.dart';
import '../../../core/image/image_processor.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/utils/file_names.dart';
import '../../../core/utils/logger.dart';
import '../../../data/local/download_store.dart';
import '../../../data/models/download_record.dart';
import '../../../data/models/jm_chapter.dart';
import '../../../data/sources/jm_api_client.dart';
import 'download_task.dart';
import 'notification_service.dart';
import 'pdf_exporter.dart';
import 'pdf_sink.dart';

/// 阅读器结束页导出的任务参数。
///
/// 与 [DownloadWorker]（整本、逐章逐页从网络抓）不同：这里优先吃阅读器已经解码好的
/// 页面字节，缺页才由 [fetchPage] 走既有加载管线（`AlbumRepository.loadPage`）补齐；
/// 页序固定 1..total，页面逐页落临时文件后交给 [PdfExporter.exportFiles]。
class ReaderExportJob {
  const ReaderExportJob({
    required this.albumId,
    required this.chapterId,
    required this.total,
    this.albumTitle = '',
    this.chapterTitle = '',
    this.cachedPages = 0,
    this.fetchPage,
  });

  final String albumId;
  final String chapterId;

  /// 专辑标题（原始值，可能为空）。为空时文件名只写 JM 号，
  /// **不**回落到章节名，也**不**让 `pdfName` 退化成 `comic` 这种泛名。
  final String albumTitle;

  /// 章节标题（原始值，可能为空）；与 [albumTitle] 分开存放，便于持久化后重建任务。
  final String chapterTitle;

  /// 当前阅读单元（章节）的总页数，也是导出的页数。
  final int total;

  /// 入队时阅读缓存里已命中的页数（只用于进度文案，不参与正确性判断）。
  final int cachedPages;

  /// 单页取字节：调用方优先读阅读缓存，缺页再走既有加载管线。
  ///
  /// 为 null 表示内存里的缓存闭包已经不可用（例如进程重启后从下载页重试），
  /// 这时按既有 API 重新取本章页面。
  final Future<Uint8List?> Function(int page)? fetchPage;

  String get displayAlbumTitle {
    final title = albumTitle.trim();
    return title.isEmpty ? 'JM$albumId' : title;
  }

  String get displayChapterTitle {
    final title = chapterTitle.trim();
    return title.isEmpty ? '第 1 话' : title;
  }

  /// 期望的 PDF 文件名。
  String get requestedPdfName {
    final title = albumTitle.trim();
    return title.isEmpty ? 'JM$albumId.pdf' : pdfName(albumId, title);
  }

  /// 去重键：同一本的同一章只保留一个进行中的导出任务。
  String get scopeKey => '$albumId/$chapterId';
}

/// 阅读器页面级导出：缓存优先、缺页补齐、按页序落临时文件并合成 PDF。
///
/// 内存策略与 [DownloadWorker] 对齐：页面字节只在当前循环内驻留，写完临时 PNG
/// 立刻释放；PDF 生成阶段只按文件路径逐页读取，不会把整章 `Uint8List` 攒在内存里。
/// 无论成功 / 失败 / 取消，临时页目录都在 `finally` 里删除。
class ReaderExportWorker {
  ReaderExportWorker({
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

  /// 进度节流状态按 workId 隔离（同一个 worker 会被多个并发任务复用）。
  final Map<String, ({String status, int percent, DateTime at})> _throttle =
      <String, ({String status, int percent, DateTime at})>{};

  Future<void> run(
    String workId,
    ReaderExportJob job,
    CancellationToken token,
  ) async {
    token.throwIfCancelled();
    final workDir = await _createWorkDir(workId);
    try {
      await _write(
        workId,
        (record) => record.copyWith(
          state: DownloadState.running,
          status: '正在整理阅读缓存',
          detail: job.cachedPages > 0 && job.total > 0
              ? '复用 ${job.cachedPages}/${job.total} 页阅读缓存，其余按需补齐'
              : '缓存里还没有页面，将按页序从线路补齐',
          done: 0,
          total: job.total,
          percent: 0,
        ),
      );
      await _notify('JM${job.albumId}', job.displayChapterTitle);

      final fetcher = job.fetchPage;
      final apiFetcher =
          fetcher == null ? _ApiPageFetcher(await _apiLoader(), job) : null;
      final fetch = fetcher ?? apiFetcher!.fetch;

      // 兼容旧记录 / 异常路径：total 缺失时按既有 API 恢复章节页数并写回记录，
      // 不能拿 0 页去「导出成功」。
      var total = job.total;
      if (total <= 0) {
        if (apiFetcher == null) {
          throw const JmContentException('缺少章节页数，无法导出');
        }
        total = await apiFetcher.pageCount();
        if (total <= 0) {
          throw const JmContentException('无法确定章节页数');
        }
        await _write(workId, (record) => record.copyWith(total: total));
      }

      final pages = <File>[];
      final missing = <int>[];
      for (var page = 1; page <= total; page++) {
        token.throwIfCancelled();
        final bytes = await _loadPage(page, fetch, token);
        if (bytes == null || bytes.isEmpty) {
          missing.add(page);
          Log.w('阅读器导出缺页：JM${job.albumId} 第 $page 页');
        } else {
          // 字节只在这一轮内驻留：落成临时 PNG 后即可被回收。
          final target = File(
            '${workDir.path}${Platform.pathSeparator}'
            '${page.toString().padLeft(5, '0')}.png',
          );
          await target.writeAsBytes(bytes, flush: true);
          pages.add(target);
        }
        await _report(
          workId,
          '正在合并页面',
          '${job.displayChapterTitle} · 第 $page/$total 页',
          page,
          total,
        );
      }
      token.throwIfCancelled();

      // 缺页不静默当成功（PLAN §11 的页面级版本）：宁可任务失败，也不产出缺页 PDF。
      if (missing.isNotEmpty) {
        throw JmContentException('第 ${missing.join('、')} 页没有取到，未生成 PDF');
      }
      if (pages.isEmpty) {
        throw const JmContentException('这本漫画没有可导出的页面');
      }

      await _report(
        workId,
        '正在生成 PDF',
        '共 ${pages.length} 页，正在逐页写入',
        pages.length,
        pages.length,
        force: true,
      );
      await _notify('正在生成 PDF', 'JM${job.albumId} · ${pages.length} 页');

      final pdfBytes = await PdfExporter.exportFiles(pages);
      // 写盘之前仍然可以取消：这时还没产生任何 PDF 文件。
      token.throwIfCancelled();

      final exported = await _sink.write(job.requestedPdfName, pdfBytes);
      // 从这里开始 PDF 已经真实落盘：取消不能再把记录改回「已取消」，
      // 否则会留下无主 PDF、并谎称临时文件已清理。写盘阶段视为不可取消的提交点。
      await _commitSuccess(workId, job, exported, pages.length);
      await _notify('下载完成', exported.name);
      Log.i('阅读器导出完成：${exported.name}');
    } finally {
      _throttle.remove(workId);
      await _deleteQuietly(workDir);
    }
  }

  /// 成功提交：直接写 history，绕过 `_write` 的「已取消不回写」保护。
  ///
  /// 原因：`_sink.write` 完成时 PDF 已存在，这条记录的最终事实就是「已完成」；
  /// 若此时记录仍是 cancelled，下载页会出现「已取消」但文件在磁盘上的无主产物。
  Future<void> _commitSuccess(
    String workId,
    ReaderExportJob job,
    PdfExportResult exported,
    int pageCount,
  ) {
    return _history.update(workId, (record) {
      return record.copyWith(
        state: DownloadState.succeeded,
        status: '导出完成',
        // 存原始专辑标题（可能为空），展示时由 displayTitle 回落 JM 号。
        title: job.albumTitle,
        chapterTitle: job.chapterTitle,
        detail: '',
        done: pageCount,
        total: pageCount,
        percent: 100,
        pageCount: pageCount,
        pdfName: exported.name,
        pdfUri: exported.uri,
        pdfPath: exported.path,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
        clearError: true,
      );
    });
  }

  Future<Directory> _createWorkDir(String workId) async {
    final root = await _workRoot();
    final dir = Directory('${root.path}${Platform.pathSeparator}$workId');
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    dir.createSync(recursive: true);
    return dir;
  }

  Future<Directory> _workRoot() async {
    final override = _workRootOverride;
    if (override != null) {
      if (!override.existsSync()) override.createSync(recursive: true);
      return override;
    }
    final cache = await getTemporaryDirectory();
    final root = Directory('${cache.path}${Platform.pathSeparator}jm-export');
    if (!root.existsSync()) root.createSync(recursive: true);
    return root;
  }

  static Future<void> _deleteQuietly(Directory dir) async {
    try {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    } catch (error) {
      Log.w('清理导出临时目录失败：$error');
    }
  }

  /// 单页取字节：可重试的 IO 错误重试，业务错误直接抛。
  Future<Uint8List?> _loadPage(
    int page,
    Future<Uint8List?> Function(int page) fetch,
    CancellationToken token,
  ) async {
    for (var attempt = 0; attempt <= AppConfig.maxIoRetries; attempt++) {
      token.throwIfCancelled();
      try {
        final bytes = await fetch(page);
        if (bytes != null && bytes.isNotEmpty) return bytes;
      } on JmCancelledException {
        rethrow;
      } on JmContentException {
        rethrow;
      } catch (error) {
        Log.w('第 $page 页取字节失败（第 ${attempt + 1} 次）：$error');
      }
      if (attempt < AppConfig.maxIoRetries) {
        await Future<void>.delayed(Duration(milliseconds: 200 * (attempt + 1)));
      }
    }
    return null;
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
    final percent =
        total > 0 ? ((done * 100) ~/ total).clamp(0, 100).toInt() : 0;
    final now = DateTime.now();
    final last = _throttle[workId];
    final changed =
        last == null || status != last.status || percent != last.percent;
    final elapsed =
        last == null ? const Duration(days: 1) : now.difference(last.at);
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
    final message = text.replaceAll('\n', ' · ');
    await _notifications?.update(title: title, text: message);
  }
}

/// 没有阅读缓存闭包时的兜底取页：按既有 API 重新取本章（进程重启后重试会走这里）。
class _ApiPageFetcher {
  _ApiPageFetcher(this._api, this._job);

  final JmApi _api;
  final ReaderExportJob _job;

  JmChapter? _chapter;
  int? _scramble;

  Future<JmChapter> _loadChapter() async => _chapter ??= await _api.getChapter(
        JmChapterRef(id: _job.chapterId, title: _job.chapterTitle),
      );

  /// 章节页数（记录里 total 丢失时用来恢复）。
  Future<int> pageCount() async => (await _loadChapter()).images.length;

  Future<Uint8List?> fetch(int page) async {
    final chapter = await _loadChapter();
    if (page < 1 || page > chapter.images.length) return null;
    final filename = chapter.images[page - 1];
    final raw = await _api.downloadImage(_job.chapterId, filename);
    final scramble = _scramble ??= await _api.getScrambleId(_job.chapterId);
    return ImageProcessor.restore(
      RestoreRequest(
        raw: raw,
        scrambleId: scramble,
        photoId: int.tryParse(_job.chapterId) ?? 0,
        filename: filename,
      ),
    );
  }
}
