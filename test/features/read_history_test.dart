import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:jm_comic/data/local/hive_init.dart';
import 'package:jm_comic/data/local/progress_store.dart';

import '../helpers/test_env.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initTestStores();
  });

  setUp(() async {
    await clearTestBoxes();
  });

  ProgressStore buildStore() =>
      ProgressStore(Hive.box<dynamic>(HiveBoxes.readerProgress));

  test('阅读历史按最近阅读倒序，缺标题时回落到 JM 车号', () async {
    final store = buildStore();
    await store.write(
      '1',
      '11',
      const ReaderProgress(
        page: 5,
        total: 10,
        updatedAt: 1000,
        albumTitle: '甲本',
        chapterTitle: '第 1 话',
      ),
    );
    await store.write(
      '2',
      '22',
      const ReaderProgress(page: 1, total: 3, updatedAt: 3000),
    );

    final entries = store.entries();
    expect(entries, hasLength(2));
    expect(entries.first.albumId, '2');
    expect(entries.first.chapterId, '22');
    expect(entries.first.displayTitle, 'JM2');
    expect(entries.first.progress.percent, 33);
    expect(entries.last.displayTitle, '甲本');
    expect(entries.last.subtitle, contains('第 1 话'));
    expect(entries.last.progress.percent, 50);
  });

  test('删除单条与清空阅读历史', () async {
    final store = buildStore();
    await store.write('1', '11', const ReaderProgress(page: 1, total: 2, updatedAt: 10));
    await store.write('2', '22', const ReaderProgress(page: 2, total: 2, updatedAt: 20));

    await store.remove('1', '11');
    expect(store.historyCount, 1);
    expect(store.entries().single.albumId, '2');

    await store.clear();
    expect(store.entries(), isEmpty);
  });

  test('非 progress 键不会污染阅读历史', () async {
    await Hive.box<dynamic>(HiveBoxes.readerProgress).put('junk', <String, dynamic>{});
    expect(buildStore().entries(), isEmpty);
  });

  test('本地 PDF 页码按 URI 保存，清空漫画历史后仍可续读', () async {
    final store = buildStore();
    await store.writePdfPage('content://pdf/1', 8);
    await store.writePdfPage('content://pdf/2', 3);
    expect(store.historyCount, 0);
    expect(store.entries(), isEmpty);
    await store.clear();
    expect(buildStore().readPdfPage('content://pdf/1'), 8);
    expect(buildStore().readPdfPage('content://pdf/2'), 3);
  });
}
