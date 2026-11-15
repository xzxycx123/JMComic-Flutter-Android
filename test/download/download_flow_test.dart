import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jm_comic/data/local/download_store.dart';
import 'package:jm_comic/data/models/download_record.dart';
import 'package:jm_comic/data/repositories/download_repository.dart';
import 'package:jm_comic/features/download/engine/pdf_sink.dart';

import '../helpers/fixtures.dart';

Future<void> _waitFor(bool Function() predicate, {Duration timeout = const Duration(seconds: 20)}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (predicate()) return;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  throw StateError('等待超时');
}

Future<bool> _waitForBool(
  bool Function() predicate, {
  Duration timeout = const Duration(seconds: 3),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (predicate()) return true;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  return predicate();
}

void main() {
  late Directory workRoot;
  late MemoryDownloadHistory history;
  late MemoryPdfSink sink;
  late DownloadRepository repository;
  late FakeJmApi api;

  setUp(() async {
    workRoot = await Directory.systemTemp.createTemp('jm_download_test_');
    history = MemoryDownloadHistory();
    sink = MemoryPdfSink();
    api = FakeJmApi(chapterCount: 2, pagesPerChapter: 3);
    repository = DownloadRepository(
      apiLoader: () async => api,
      history: history,
      sink: sink,
      workRoot: workRoot,
    );
  });

  tearDown(() async {
    if (workRoot.existsSync()) {
      workRoot.deleteSync(recursive: true);
    }
  });

  test('单任务：queued → running → succeeded，页数与命名正确', () async {
    final record = await repository.enqueue('350234');
    expect(record.state, DownloadState.queued);

    await _waitFor(() => history.records.first.state == DownloadState.succeeded);

    final finished = history.records.first;
    expect(finished.pageCount, 6);
    expect(finished.percent, 100);
    expect(finished.pdfName, 'JM350234 - 测试用单本漫画.pdf');
    expect(sink.files.length, 1);
    expect(sink.files.keys.first, 'JM350234 - 测试用单本漫画.pdf');
    // 临时目录在任务结束后清空
    expect(workRoot.listSync().whereType<Directory>(), isEmpty);
    expect(api.downloadCalls, 6);
  });

  test('重复下载生成 (2) 且批量输入去重保序', () async {
    final first = await repository.enqueueInput('350234 JM350235 abc');
    expect(first.added, 2);
    expect(first.skipped, 0);

    await _waitFor(
      () => history.records.every((record) => record.isFinished),
    );
    expect(sink.files.length, 2);

    // 同一本再下一次：命名递增到 (2)
    await repository.enqueue('350234');
    await _waitFor(() => sink.files.length == 3);
    expect(
      sink.files.keys.any((name) => name.contains('(2).pdf')),
      isTrue,
    );
  });

  test('取消：任务停在 cancelled，临时目录清空，不再继续下载', () async {
    final gate = Completer<void>();
    final gatedApi = FakeJmApi(chapterCount: 1, pagesPerChapter: 3, gate: gate);
    final gatedRepository = DownloadRepository(
      apiLoader: () async => gatedApi,
      history: history,
      sink: sink,
      workRoot: workRoot,
    );

    final record = await gatedRepository.enqueue('350234');
    await _waitFor(() => gatedApi.downloadCalls > 0);

    await gatedRepository.cancel(record.workId);
    gate.complete();

    await _waitFor(
      () => history.records.first.state == DownloadState.cancelled,
    );
    final callsAfterCancel = gatedApi.downloadCalls;

    // 临时工作目录必须被清空（PLAN §2.2：取消后临时文件清空）。
    // 取消信号在下一个检查点才生效，这里轮询到清空为止（最多 3s），避免时序抖动。
    final cleared = await _waitForBool(
      () => workRoot.listSync().whereType<Directory>().isEmpty,
    );
    expect(cleared, isTrue, reason: '取消后临时目录应被清空');
    expect(gatedApi.downloadCalls, callsAfterCancel);
    expect(history.records.first.state, DownloadState.cancelled);

    await repository.clearFinished();
    expect(history.records.where((record) => record.isFinished).length, 0);
  });

  test('失败页达到 3 页 → 整任务 failed（不静默缺页）', () async {
    final failingApi = FakeJmApi(failEveryPage: true);
    final failingRepository = DownloadRepository(
      apiLoader: () async => failingApi,
      history: history,
      sink: sink,
      workRoot: workRoot,
    );

    await failingRepository.enqueue('350234');
    await _waitFor(
      () => history.records.first.state == DownloadState.failed,
      timeout: const Duration(seconds: 30),
    );

    final record = history.records.first;
    expect(record.state, DownloadState.failed);
    expect(record.error, contains('页下载失败'));
    expect(sink.files, isEmpty);
  });

  test('启动时把僵尸 running 标记成 failed', () async {
    await history.add(
      const DownloadRecord(
        workId: 'w-zombie',
        albumId: '350234',
        state: DownloadState.running,
        status: '下载中',
        createdAt: 1,
        updatedAt: 1,
      ),
    );
    final count = await repository.recoverInterrupted();
    expect(count, 1);
    final record = history.records.firstWhere((item) => item.workId == 'w-zombie');
    expect(record.state, DownloadState.failed);
    expect(record.error, '进程被系统回收');
  });
}
