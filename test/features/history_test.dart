import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jm_comic/core/di/providers.dart';
import 'package:jm_comic/data/local/download_store.dart';
import 'package:jm_comic/data/models/download_record.dart';
import 'package:jm_comic/features/download/history_page.dart';

import '../helpers/test_env.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initTestStores();
  });

  setUp(() async {
    await clearTestBoxes();
  });

  test('HistoryFilter 按状态筛选', () {
    const succeeded = DownloadRecord(
      workId: 'a',
      albumId: '1',
      state: DownloadState.succeeded,
      pageCount: 3,
    );
    const failed = DownloadRecord(
      workId: 'b',
      albumId: '2',
      state: DownloadState.failed,
      error: 'boom',
    );
    const running = DownloadRecord(workId: 'c', albumId: '3', state: DownloadState.running);

    expect(HistoryFilter.succeeded.matches(succeeded), isTrue);
    expect(HistoryFilter.succeeded.matches(failed), isFalse);
    expect(HistoryFilter.failed.matches(failed), isTrue);
    expect(HistoryFilter.all.matches(running), isFalse, reason: '进行中的任务不进历史');
    expect(HistoryFilter.all.matches(succeeded), isTrue);
  });

  test('historySummary 汇总完成/失败数量', () {
    expect(historySummary(const <DownloadRecord>[]), '');
    expect(
      historySummary(const <DownloadRecord>[
        DownloadRecord(workId: 'a', albumId: '1', state: DownloadState.succeeded),
        DownloadRecord(workId: 'b', albumId: '2', state: DownloadState.failed),
        DownloadRecord(workId: 'c', albumId: '3', state: DownloadState.succeeded),
      ]),
      '完成 2 · 失败 1',
    );
  });

  testWidgets('历史页空态 + 筛选切换', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          downloadHistoryProvider.overrideWithValue(MemoryDownloadHistory()),
        ],
        child: const MaterialApp(home: HistoryPage()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('历史记录'), findsOneWidget);
    expect(find.text('还没有下载记录'), findsOneWidget);

    await tester.tap(find.text('失败'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('这个筛选下没有记录'), findsOneWidget);
  });
}
