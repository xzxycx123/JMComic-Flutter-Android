import 'package:hive_ce_flutter/hive_flutter.dart';

import '../../core/utils/logger.dart';

/// Hive box 名称表 + 初始化。
abstract final class HiveBoxes {
  static const String settings = 'jm_settings';
  static const String downloads = 'jm_downloads';
  static const String feedCache = 'jm_feed_cache';
  static const String readerProgress = 'jm_reader_progress';
  static const String searchHistory = 'jm_search_history';
  static const String favorites = 'jm_favorites';
  static const String favoriteFolders = 'jm_favorite_folders';
  static const String favoriteOutbox = 'jm_favorite_outbox';
  static const String session = 'jm_session';
  static const String endpoints = 'jm_endpoints';

  /// 每日签到：键为 `yyyy-MM-dd`。
  static const String checkIns = 'jm_check_ins';
}

abstract final class HiveInit {
  /// 幂等：重复调用安全。
  static Future<void> initialize({String? subDir}) async {
    if (subDir == null) {
      await Hive.initFlutter();
    } else {
      await Hive.initFlutter(subDir);
    }
    for (final name in <String>[
      HiveBoxes.settings,
      HiveBoxes.downloads,
      HiveBoxes.feedCache,
      HiveBoxes.readerProgress,
      HiveBoxes.searchHistory,
      HiveBoxes.favorites,
      HiveBoxes.favoriteFolders,
      HiveBoxes.favoriteOutbox,
      HiveBoxes.session,
      HiveBoxes.checkIns,
    ]) {
      if (!Hive.isBoxOpen(name)) {
        await Hive.openBox<dynamic>(name);
      }
    }
    Log.i('Hive 初始化完成');
  }

  static Future<void> close() => Hive.close();
}
