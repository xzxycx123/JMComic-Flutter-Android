import 'package:hive_ce/hive.dart';

import '../models/json_field.dart';
import 'hive_init.dart';

/// 阅读进度（Hive key: `progress:{albumId}:{chapterId}`）。
class ReaderProgress {
  const ReaderProgress({
    required this.page,
    required this.total,
    required this.updatedAt,
  });

  final int page;
  final int total;
  final int updatedAt;

  double get ratio => total <= 0 ? 0 : (page.clamp(1, total)) / total;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'page': page,
        'total': total,
        'updatedAt': updatedAt,
      };

  factory ReaderProgress.fromJson(Map<String, dynamic> json) => ReaderProgress(
        page: asInt(json['page'], 1),
        total: asInt(json['total']),
        updatedAt: asInt(json['updatedAt']),
      );
}

class ProgressStore {
  ProgressStore(this._box);

  final Box<dynamic> _box;

  static String keyFor(String albumId, String chapterId) =>
      'progress:$albumId:$chapterId';

  ReaderProgress? read(String albumId, String chapterId) {
    final raw = _box.get(keyFor(albumId, chapterId));
    if (raw is! Map) return null;
    final map = raw.map((key, value) => MapEntry('$key', value));
    return ReaderProgress.fromJson(map);
  }

  Future<void> write(String albumId, String chapterId, ReaderProgress progress) async {
    await _box.put(keyFor(albumId, chapterId), progress.toJson());
  }

  Future<void> remove(String albumId, String chapterId) async {
    await _box.delete(keyFor(albumId, chapterId));
  }

  /// 阅读历史条数（我的页统计）。
  int get historyCount => _box.keys.length;

  Future<void> clear() => _box.clear();
}

class SearchHistoryStore {
  SearchHistoryStore(this._box);

  static const String _key = 'history';
  final Box<dynamic> _box;

  List<String> read() {
    final raw = _box.get(_key);
    if (raw is List) {
      return raw.map((item) => '$item').toList(growable: false);
    }
    return const <String>[];
  }

  Future<List<String>> push(String keyword, {int limit = 10}) async {
    final value = keyword.trim();
    if (value.isEmpty) return read();
    final next = <String>[
      value,
      ...read().where((item) => item != value),
    ].take(limit).toList(growable: false);
    await _box.put(_key, next);
    return next;
  }

  Future<void> clear() => _box.delete(_key);
}

/// 本地收藏（v1 只存 id，不接登录接口）。
/// 统一取 box 的小工具（冷启动时必须已 [HiveInit.initialize]）。
Box<dynamic> appBox(String name) => Hive.box<dynamic>(name);
