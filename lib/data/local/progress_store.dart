import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
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

  String get displayTitle => progress.albumTitle.trim().isEmpty
      ? 'JM$albumId'
      : progress.albumTitle.trim();

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

  static String _pdfKey(String uri) =>
      'pdf:${sha256.convert(utf8.encode(uri))}';

  int? readPdfPage(String uri) {
    final value = _box.get(_pdfKey(uri));
    return value is int ? value : null;
  }

  Future<void> writePdfPage(String uri, int page) =>
      _box.put(_pdfKey(uri), page);

  Iterable<dynamic> get _onlineKeys =>
      _box.keys.where((key) => key is String && key.startsWith('progress:'));

  /// 落盘版本号：每次 write / remove / clear 之后 +1。
  ///
  /// 普通 `Provider<ProgressStore>` 不会因为 Hive `put` 自动失效，
  /// Riverpod 侧靠这个版本号让 `chapterProgressProvider` 之类的 Provider 重算。
  int _revision = 0;
  final List<void Function()> _listeners = <void Function()>[];

  int get revision => _revision;

  void addListener(void Function() listener) => _listeners.add(listener);

  void removeListener(void Function() listener) => _listeners.remove(listener);

  /// 手动广播一次「进度已变更」。
  ///
  /// 只有直接改 box（绕过 [write]）或测试替身才需要；正常写入会自动广播。
  void notifyChanged() => _markChanged();

  void _markChanged() {
    _revision++;
    // 复制一份再遍历：监听器里可能立刻反注册。
    for (final listener in List<void Function()>.of(_listeners)) {
      listener();
    }
  }

  ReaderProgress? read(String albumId, String chapterId) {
    final raw = _box.get(keyFor(albumId, chapterId));
    if (raw is! Map) return null;
    final map = raw.map((key, value) => MapEntry('$key', value));
    return ReaderProgress.fromJson(map);
  }

  Future<void> write(
    String albumId,
    String chapterId,
    ReaderProgress progress,
  ) async {
    await _box.put(keyFor(albumId, chapterId), progress.toJson());
    _markChanged();
  }

  Future<void> remove(String albumId, String chapterId) async {
    await _box.delete(keyFor(albumId, chapterId));
    _markChanged();
  }

  /// 阅读历史条数（我的页统计）。
  int get historyCount => _onlineKeys.length;

  /// 全部阅读进度，按最近阅读时间倒序（阅读历史页用）。
  List<ReadingHistoryEntry> entries() {
    final result = <ReadingHistoryEntry>[];
    for (final key in _onlineKeys) {
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

  Future<void> clear() async {
    await _box.deleteAll(_onlineKeys.toList(growable: false));
    _markChanged();
  }
}

/// 一次阅读进度落盘快照：脱离 widget 树构造，dispose / 系统返回时也能直接取。
class ProgressSnapshot {
  const ProgressSnapshot({
    required this.albumId,
    required this.chapterId,
    required this.page,
    required this.total,
    this.albumTitle = '',
    this.chapterTitle = '',
  });

  final String albumId;
  final String chapterId;
  final int page;
  final int total;
  final String albumTitle;
  final String chapterTitle;

  /// 缺 album / chapter 的进度没有意义（写进去会污染阅读历史）。
  bool get isEmpty => albumId.isEmpty || chapterId.isEmpty;

  ReaderProgress toProgress(int updatedAt) => ReaderProgress(
        page: page,
        total: total,
        updatedAt: updatedAt,
        albumTitle: albumTitle,
        chapterTitle: chapterTitle,
      );
}

/// 阅读进度落盘器：**写入串行化 + 最后一次写入优先**。
///
/// 1. [record] 只把最新快照放进队列：尚未开始写的旧快照直接被覆盖，
///    因此「旧页异步慢一步落地、把新页盖回去」不会发生；
/// 2. 队列由唯一 worker 顺序消费，同一时刻最多一次 Hive `put`；
/// 3. [record] 返回的 future 在「本次快照或更新的快照」真正落盘后完成；
/// 4. [flush] 等队列清空，供 HUD 退出 / dispose 使用。
class ProgressRecorder {
  ProgressRecorder({
    required ProgressStore store,
    DateTime Function()? clock,
  })  : _store = store,
        _clock = clock ?? DateTime.now;

  final ProgressStore _store;
  final DateTime Function() _clock;

  ProgressSnapshot? _queued;
  final List<Completer<void>> _waiters = <Completer<void>>[];
  Future<void>? _worker;
  Object? _lastError;
  int _writes = 0;

  /// 实际落盘次数（被覆盖的快照不计），用于诊断与测试。
  int get writes => _writes;

  Object? get lastError => _lastError;

  bool get idle => _worker == null;

  Future<void> record(ProgressSnapshot snapshot) {
    if (snapshot.isEmpty) return Future<void>.value();
    _queued = snapshot;
    final waiter = Completer<void>();
    _waiters.add(waiter);
    _schedule();
    return waiter.future;
  }

  /// 等当前队列全部落盘（录制期间又来的快照也会一起写掉）。
  Future<void> flush() async {
    while (true) {
      final worker = _worker;
      if (worker == null) {
        if (_queued == null) return;
        _schedule();
        continue;
      }
      await worker;
      if (identical(worker, _worker)) return;
    }
  }

  void _schedule() {
    if (_worker != null) return;
    _worker = _drain().whenComplete(() {
      _worker = null;
      // 兜底：worker 收尾瞬间进来的快照不能丢。
      if (_queued != null) _schedule();
    });
  }

  Future<void> _drain() async {
    while (true) {
      final snapshot = _queued;
      if (snapshot == null) return;
      _queued = null;
      final waiters = List<Completer<void>>.of(_waiters);
      _waiters.clear();
      try {
        await _store.write(
          snapshot.albumId,
          snapshot.chapterId,
          snapshot.toProgress(_clock().millisecondsSinceEpoch),
        );
        _writes++;
        _lastError = null;
      } catch (error) {
        _lastError = error;
      }
      for (final waiter in waiters) {
        if (!waiter.isCompleted) waiter.complete();
      }
    }
  }
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

  Future<void> remove(String keyword) async {
    final current = read();
    final next =
        current.where((item) => item != keyword).toList(growable: false);
    if (next.length != current.length) await _box.put(_key, next);
  }

  Future<void> clear() => _box.delete(_key);
}

/// 统一取 box 的小工具（冷启动时必须已 [HiveInit.initialize]）。
Box<dynamic> appBox(String name) => Hive.box<dynamic>(name);
