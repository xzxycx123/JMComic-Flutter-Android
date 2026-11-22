import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:jm_comic/data/local/download_store.dart';
import 'package:jm_comic/data/models/download_record.dart';
import 'package:jm_comic/data/repositories/download_repository.dart';
import 'package:jm_comic/features/download/engine/pdf_sink.dart';
import 'package:jm_comic/features/download/engine/reader_export_worker.dart';

import '../helpers/fixtures.dart';

Future<void> _waitForState(
  DownloadHistory history,
  DownloadState state, {
  int index = 0,
  Duration timeout = const Duration(seconds: 10),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (history.records.length > index &&
        history.records[index].state == state) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  final current =
      history.records.isEmpty ? '空' : history.records.first.state.name;
  throw StateError('等待 ${state.name} 超时，当前：$current');
}

Future<void> _waitFor(
  bool Function() predicate, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (predicate()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(predicate(), isTrue);
}

/// 从 PDF 字节里按出现顺序抽 `/MediaBox [0 0 w h]`，用来证明页序与页尺寸。
List<({double width, double height})> _mediaBoxes(Uint8List bytes) {
  final text = latin1.decode(bytes, allowInvalid: true);
  final pattern = RegExp(
    r'/MediaBox\s*\[\s*[0-9.]+\s+[0-9.]+\s+([0-9.]+)\s+([0-9.]+)\s*\]',
  );
  return <({double width, double height})>[
    for (final match in pattern.allMatches(text))
      (
        width: double.parse(match.group(1)!),
        height: double.parse(match.group(2)!),
      ),
  ];
}

/// 可控写盘器：写入过程可以挂起，用来覆盖「写盘期间取消」的窗口。
class _GatedPdfSink extends MemoryPdfSink {
  final Completer<void> entered = Completer<void>();
  final Completer<void> gate = Completer<void>();

  @override
  Future<PdfExportResult> write(String requestedName, Uint8List bytes) async {
    if (!entered.isCompleted) entered.complete();
    await gate.future;
    return super.write(requestedName, bytes);
  }
}

void main() {
  late Directory workRoot;
  late MemoryDownloadHistory history;
  late MemoryPdfSink sink;
  late FakeJmApi api;
  late DownloadRepository repository;

  setUp(() async {
    workRoot = await Directory.systemTemp.createTemp('jm_export_test_');
    history = MemoryDownloadHistory();
    sink = MemoryPdfSink();
    api = FakeJmApi(chapterCount: 1, pagesPerChapter: 3);
    repository = DownloadRepository(
      apiLoader: () async => api,
      history: history,
      sink: sink,
      workRoot: workRoot,
    );
  });

  tearDown(() async {
    // 任务收尾可能还在删临时目录：等一小会儿再删根目录，删不掉也不算用例失败。
    for (var attempt = 0; attempt < 50; attempt++) {
      try {
        if (workRoot.existsSync()) workRoot.deleteSync(recursive: true);
        return;
      } catch (_) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    }
  });

  ReaderExportJob job({
    int total = 4,
    String albumTitle = '测试本',
    String chapterTitle = '第 1 话',
    int cachedPages = 0,
    Future<Uint8List?> Function(int page)? fetchPage,
  }) =>
      ReaderExportJob(
        albumId: '7000',
        chapterId: '7999',
        albumTitle: albumTitle,
        chapterTitle: chapterTitle,
        total: total,
        cachedPages: cachedPages,
        fetchPage: fetchPage,
      );

  /// 每页尺寸不同，便于从 PDF 里反推真实页序。
  Uint8List pagePng(int page) => switch (page) {
        1 => syntheticPng(width: 40, height: 60, seed: 1),
        2 => syntheticPng(width: 60, height: 40, seed: 2),
        3 => syntheticPng(width: 50, height: 70, seed: 3),
        _ => syntheticPng(width: 70, height: 50, seed: 4),
      };

  test('缓存命中 + 缺页补齐：只请求缺页，按 1..total 页序与尺寸写进 PDF', () async {
    final cached = <int, Uint8List>{1: pagePng(1), 2: pagePng(2)};
    final requests = <int, int>{};

    await repository.enqueueReaderExport(
      job(
        total: 4,
        cachedPages: 2,
        fetchPage: (page) async {
          final hit = cached[page];
          if (hit != null) return hit;
          requests[page] = (requests[page] ?? 0) + 1;
          // 第 3 页第一次失败，验证单页重试；第 4 页一次成功。
          if (page == 3 && requests[page] == 1) return null;
          return pagePng(page);
        },
      ),
    );

    await _waitForState(history, DownloadState.succeeded);
    final record = history.records.first;

    expect(record.pageCount, 4);
    expect(record.percent, 100);
    expect(record.chapterId, '7999');
    expect(record.chapterTitle, '第 1 话');
    expect(record.title, '测试本');
    expect(record.pdfName, 'JM7000 - 测试本.pdf');
    expect(requests.keys.toList(), <int>[3, 4], reason: '缓存命中页不发起加载');
    expect(requests[3], 2);
    expect(requests[4], 1);

    final boxes = _mediaBoxes(sink.files.values.single);
    expect(boxes, hasLength(4));
    expect(boxes[0].width, 40);
    expect(boxes[0].height, 60);
    expect(boxes[1].width, 60);
    expect(boxes[1].height, 40);
    expect(boxes[2].width, 50);
    expect(boxes[2].height, 70);
    expect(boxes[3].width, 70);
    expect(boxes[3].height, 50);
    // 临时页目录用完即清。
    await _waitFor(() => workRoot.listSync().isEmpty);
  });

  test('永久缺页：任务失败、不产出 PDF、错误带页码、临时目录清空', () async {
    await repository.enqueueReaderExport(
      job(
        total: 3,
        fetchPage: (page) async => page == 2 ? null : pagePng(page),
      ),
    );

    await _waitForState(history, DownloadState.failed);
    final record = history.records.first;

    expect(record.state, isNot(DownloadState.succeeded));
    expect(record.error, contains('第 2 页'));
    expect(record.pageCount, 0);
    expect(sink.files, isEmpty, reason: '缺页时不能产出「成功」的 PDF');
    await _waitFor(() => workRoot.listSync().isEmpty);
  });

  test('取页阶段取消：cancelled、无 PDF、临时目录清空', () async {
    final gate = Completer<void>();
    final ticket = await repository.enqueueReaderExport(
      job(
        total: 3,
        fetchPage: (page) async {
          if (page == 1) await gate.future;
          return pagePng(page);
        },
      ),
    );
    await _waitForState(history, DownloadState.running);

    await repository.cancel(ticket.record.workId);
    gate.complete();

    await _waitForState(history, DownloadState.cancelled);
    expect(sink.files, isEmpty);
    await _waitFor(() => workRoot.listSync().isEmpty);
  });

  test('写盘期间取消：PDF 已落盘则提交为成功，记录不谎称已清理', () async {
    final gatedSink = _GatedPdfSink();
    final gatedRepository = DownloadRepository(
      apiLoader: () async => api,
      history: history,
      sink: gatedSink,
      workRoot: workRoot,
    );
    final ticket = await gatedRepository.enqueueReaderExport(
      job(total: 2, fetchPage: (page) async => pagePng(page)),
    );

    await gatedSink.entered.future;
    await gatedRepository.cancel(ticket.record.workId);
    gatedSink.gate.complete();

    await _waitForState(history, DownloadState.succeeded);
    final record = history.records.first;
    expect(gatedSink.files, hasLength(1), reason: '已写出的 PDF 不能变成无主文件');
    expect(record.state, DownloadState.succeeded);
    expect(record.pdfName, isNotNull);
    expect(record.detail, isNot(contains('清理')));
    await _waitFor(() => workRoot.listSync().isEmpty);
  });

  test('重复入队去重：同一本同一章返回同一任务', () async {
    final gate = Completer<void>();
    final first = await repository.enqueueReaderExport(
      job(
        total: 2,
        fetchPage: (page) async {
          await gate.future;
          return pagePng(page);
        },
      ),
    );
    final second = await repository.enqueueReaderExport(
      job(total: 2, fetchPage: (page) async => pagePng(page)),
    );

    expect(second.reused, isTrue);
    expect(second.record.workId, first.record.workId);
    expect(history.records, hasLength(1));

    gate.complete();
    await _waitForState(history, DownloadState.succeeded);
  });

  test('整本任务进行中时，结束页下载复用既有任务（不再重复入队）', () async {
    await history.add(
      const DownloadRecord(
        workId: 'w-album',
        albumId: '7000',
        state: DownloadState.running,
        status: '下载中',
        createdAt: 1,
        updatedAt: 1,
      ),
    );

    final ticket = await repository.enqueueReaderExport(
      job(total: 2, fetchPage: (page) async => pagePng(page)),
    );

    expect(ticket.reused, isTrue);
    expect(ticket.record.workId, 'w-album');
    expect(history.records.where((r) => r.chapterId == '7999'), isEmpty);
  });

  test('反向：只有章节导出在跑时，整本 enqueue 不被吞掉', () async {
    final gate = Completer<void>();
    final chapterTicket = await repository.enqueueReaderExport(
      job(
        total: 2,
        fetchPage: (page) async {
          await gate.future;
          return pagePng(page);
        },
      ),
    );

    final albumRecord = await repository.enqueue('7000');

    expect(albumRecord.workId, isNot(chapterTicket.record.workId));
    expect(albumRecord.chapterId, isEmpty);
    expect(albumRecord.albumId, '7000');
    expect(
      history.records.where((r) => r.chapterId == '7999' && r.isActive),
      hasLength(1),
      reason: '章节导出任务不能被整本任务顶掉',
    );

    gate.complete();
    await _waitFor(
      () =>
          history.records
              .firstWhere((r) => r.workId == chapterTicket.record.workId)
              .state ==
          DownloadState.succeeded,
    );
    // 整本任务也在同一个 workRoot 下跑，收尾后再结束用例。
    await _waitFor(() => history.records.every((r) => r.isFinished));
  });

  test('反向：只有章节导出在跑时，enqueueInput 不把它当成整本已在下载', () async {
    final gate = Completer<void>();
    await repository.enqueueReaderExport(
      job(
        total: 2,
        fetchPage: (page) async {
          await gate.future;
          return pagePng(page);
        },
      ),
    );

    final result = await repository.enqueueInput('7000');

    expect(result.added, 1);
    expect(result.skipped, 0);
    await _waitFor(
      () => history.records
          .any((r) => r.chapterId.isEmpty && r.albumId == '7000'),
    );

    gate.complete();
    await _waitFor(() => history.records.every((r) => r.isFinished));
  });

  test('没有缓存闭包（进程重启后重试）时按既有 API 重新取整章页面', () async {
    await repository.enqueueReaderExport(job(total: 3));

    await _waitForState(history, DownloadState.succeeded);
    final record = history.records.first;

    expect(record.pageCount, 3);
    expect(record.chapterTitle, '第 1 话');
    expect(api.downloadCalls, 3);
    expect(api.scrambleCalls, 1, reason: '同一章的切片阈值只取一次');
    expect(sink.files, hasLength(1));
  });

  test('失败后重试：记录里的 total 不被清零，按章节重建后成功', () async {
    final ticket = await repository.enqueueReaderExport(
      job(total: 2, fetchPage: (page) async => null),
    );
    await _waitForState(history, DownloadState.failed);
    expect(history.records.first.total, 2);
    expect(sink.files, isEmpty);

    final gate = Completer<void>();
    final gatedApi = FakeJmApi(chapterCount: 1, pagesPerChapter: 2, gate: gate);
    final restarted = DownloadRepository(
      apiLoader: () async => gatedApi,
      history: history,
      sink: sink,
      workRoot: workRoot,
    );
    await restarted.retry(ticket.record.workId);

    // 入队后、真正取页前：total 必须保持原章节页数（不能持久化成 0）。
    expect(history.records.first.state, isNot(DownloadState.failed));
    expect(history.records.first.total, 2);

    gate.complete();
    await _waitForState(history, DownloadState.succeeded);
    expect(history.records.first.pdfName, 'JM7000 - 测试本.pdf');
    expect(history.records.first.chapterTitle, '第 1 话');
    expect(gatedApi.downloadCalls, 2, reason: '只补这一章，不回落成整本下载');
    expect(sink.files, hasLength(1));
  });

  test('旧记录 total 为 0：重试时从 API 恢复章节页数', () async {
    await history.add(
      const DownloadRecord(
        workId: 'w-legacy',
        albumId: '7000',
        chapterId: '7999',
        chapterTitle: '第 1 话',
        title: '测试本',
        state: DownloadState.failed,
        status: '下载失败',
        total: 0,
        createdAt: 1,
        updatedAt: 2,
      ),
    );

    final twoPageApi = FakeJmApi(chapterCount: 1, pagesPerChapter: 2);
    final restarted = DownloadRepository(
      apiLoader: () async => twoPageApi,
      history: history,
      sink: sink,
      workRoot: workRoot,
    );
    await restarted.retry('w-legacy');

    await _waitForState(history, DownloadState.succeeded);
    final record = history.records.first;
    expect(record.total, 2, reason: 'API 恢复出的章节页数要写回记录');
    expect(record.pageCount, 2);
    expect(twoPageApi.downloadCalls, 2);
    expect(sink.files, hasLength(1));
  });

  test('专辑标题为空：文件名只写 JM 号，不回落章节名也不产生 comic 泛名', () async {
    await repository.enqueueReaderExport(
      job(
        total: 2,
        albumTitle: '',
        chapterTitle: '第 7 话',
        fetchPage: (page) async => pagePng(page),
      ),
    );

    await _waitForState(history, DownloadState.succeeded);
    final record = history.records.first;
    expect(record.title, isEmpty);
    expect(record.displayTitle, 'JM7000');
    expect(record.pdfName, 'JM7000.pdf');
    expect(record.pdfName, isNot(contains('comic')));
    expect(record.pdfName, isNot(contains('第 7 话')));
    expect(record.chapterTitle, '第 7 话');
    expect(record.detail, isEmpty, reason: 'detail 不再兼职章节标题');
  });

  test('成功后再点下载会重新入队（不复用已完成任务）', () async {
    final first = await repository.enqueueReaderExport(
      job(total: 2, fetchPage: (page) async => pagePng(page)),
    );
    await _waitForState(history, DownloadState.succeeded);

    final second = await repository.enqueueReaderExport(
      job(total: 2, fetchPage: (page) async => pagePng(page)),
    );

    expect(second.reused, isFalse);
    expect(second.record.workId, isNot(first.record.workId));
    expect(history.records, hasLength(2));
    await _waitForState(history, DownloadState.succeeded, index: 0);
  });
}
