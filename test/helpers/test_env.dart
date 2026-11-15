import 'dart:io';

import 'package:hive_ce/hive.dart';
import 'package:jm_comic/data/local/hive_init.dart';
import 'package:shared_preferences/shared_preferences.dart';

bool _initialized = false;
Directory? _tempDir;

/// 测试环境：Hive 落临时目录 + SharedPreferences mock。
Future<void> initTestStores() async {
  if (_initialized) return;
  _tempDir = await Directory.systemTemp.createTemp('jm_comic_test_');
  Hive.init(_tempDir!.path);
  SharedPreferences.setMockInitialValues(<String, Object>{});
  for (final name in <String>[
    HiveBoxes.settings,
    HiveBoxes.downloads,
    HiveBoxes.feedCache,
    HiveBoxes.readerProgress,
    HiveBoxes.searchHistory,
    HiveBoxes.favorites,
  ]) {
    if (!Hive.isBoxOpen(name)) {
      await Hive.openBox<dynamic>(name);
    }
  }
  _initialized = true;
}

Future<SharedPreferences> testPreferences() async {
  await initTestStores();
  return SharedPreferences.getInstance();
}

Future<void> clearTestBoxes() async {
  for (final name in <String>[
    HiveBoxes.settings,
    HiveBoxes.downloads,
    HiveBoxes.feedCache,
    HiveBoxes.readerProgress,
    HiveBoxes.searchHistory,
    HiveBoxes.favorites,
  ]) {
    if (Hive.isBoxOpen(name)) {
      await Hive.box<dynamic>(name).clear();
    }
  }
}
