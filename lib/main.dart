import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/di/providers.dart';
import 'core/network/dio_factory.dart';
import 'data/local/download_store.dart';
import 'data/local/favorites_store.dart';
import 'data/local/hive_init.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await HiveInit.initialize();

  // 老版本 `jm_favorites = {ids:[…]}` 迁移成 per-album 记录（幂等）。
  final favoritesStore = FavoritesStore(
    favorites: Hive.box<dynamic>(HiveBoxes.favorites),
    folders: Hive.box<dynamic>(HiveBoxes.favoriteFolders),
    outbox: Hive.box<dynamic>(HiveBoxes.favoriteOutbox),
  );
  await favoritesStore.migrateIfNeeded();

  final prefs = await SharedPreferences.getInstance();
  final downloadHistory = HiveDownloadHistory(Hive.box<dynamic>(HiveBoxes.downloads));
  await downloadHistory.load();
  // 冷启动扫描「僵尸 running」：上次进程被系统回收时留下的任务标记为失败并允许重试。
  await downloadHistory.markInterrupted();

  runApp(
    ProviderScope(
      overrides: <Override>[
        sharedPreferencesProvider.overrideWithValue(prefs),
        downloadHistoryProvider.overrideWithValue(downloadHistory),
        cookieJarProvider.overrideWithValue(JmCookieJar()),
      ],
      child: const JmComicApp(),
    ),
  );
}
