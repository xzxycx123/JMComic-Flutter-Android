import 'package:hive_ce/hive.dart';

import '../models/json_field.dart';
import 'hive_init.dart';

/// 阅读进度（Hive key: `progress:{albumId}:{chapterId}`）。
class ReaderProgress {
  const ReaderProgress({
    required this.page,
    required this.total,
    required this.updatedAt,
    this.albumTitle = '',
    this.chapterTitle = '',
  });

  final int page;
  final int total;
  final int updatedAt;

  /// 阅读器写入时顺手记下标题，阅读历史页不用再逐条请求详情。
  final String albumTitle;
  final String chapterTitle;

  double get ratio => total <= 0 ? 0 : (page.clamp(1, total)) / total;

  int get percent => (ratio * 100).round();

  Map<String, dynamic> toJson() => <String, dynamic>{
        'page': page,
        'total': total,
        'updatedAt': updatedAt,
        if (albumTitle.isNotEmpty) 'albumTitle': albumTitle,
        if (chapterTitle.isNotEmpty) 'chapterTitle': chapterTitle,
      };

  factory ReaderProgress.fromJson(Map<String, dynamic> json) => ReaderProgress(
        page: asInt(json['page'], 1),
        total: asInt(json['total']),
        updatedAt: asInt(json['updatedAt']),
        albumTitle: asStringOr(json['albumTitle'], ''),
        chapterTitle: asStringOr(json['chapterTitle'], ''),
      );
}

/// 一条阅读历史（进度记录 + 从 key 里还原的专辑/章节 id）。
class ReadingHistoryEntry {
  const ReadingHistoryEntry({
    required this.albumId,
    required this.chapterId,
    required this.progress,
  });

  final String albumId;
  final String chapterId;
  final ReaderProgress progress;

  String get displayTitle =>
      progress.albumTitle.trim().isEmpty ? 'JM$albumId' : progress.albumTitle.trim();

  String get subtitle {
    final chapter = progress.chapterTitle.trim();
    if (chapter.isEmpty) return '第 ${progress.page}/${progress.total} 页';
    return '$chapter · 第 ${progress.page}/${progress.total} 页';
  }

  String get displayTime => formatHistoryTime(progress.updatedAt);
}

/// 历史时间：今天只给 HH:mm，今年给 MM-DD HH:mm，更早给 YYYY-MM-DD。
String formatHistoryTime(int timestamp) {
  if (timestamp <= 0) return '';
  final time = DateTime.fromMillisecondsSinceEpoch(timestamp);
  final now = DateTime.now();
  final minute = time.minute.toString().padLeft(2, '0');
  final hour = time.hour.toString().padLeft(2, '0');
  final month = time.month.toString().padLeft(2, '0');
  final day = time.day.toString().padLeft(2, '0');
  if (time.year == now.year && time.month == now.month && time.day == now.day) {
    return '$hour:$minute';
  }
  if (time.year == now.year) return '$month-$day $hour:$minute';
  return '${time.year}-$month-$day';
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

  /// 全部阅读进度，按最近阅读时间倒序（阅读历史页用）。
  List<ReadingHistoryEntry> entries() {
    final result = <ReadingHistoryEntry>[];
    for (final key in _box.keys) {
      final name = '$key';
      final parts = name.split(':');
      if (parts.length != 3 || parts.first != 'progress') continue;
      final raw = _box.get(key);
      if (raw is! Map) continue;
      result.add(
        ReadingHistoryEntry(
          albumId: parts[1],
          chapterId: parts[2],
          progress: ReaderProgress.fromJson(
            raw.map((mapKey, value) => MapEntry('$mapKey', value)),
          ),
        ),
      );
    }
    result.sort((a, b) => b.progress.updatedAt.compareTo(a.progress.updatedAt));
    return result;
  }

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

/// 统一取 box 的小工具（冷启动时必须已 [HiveInit.initialize]）。
Box<dynamic> appBox(String name) => Hive.box<dynamic>(name);
