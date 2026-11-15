import 'dart:async';
import 'dart:convert';

import 'package:hive_ce/hive.dart';

import '../../core/config/app_config.dart';
import '../../core/utils/logger.dart';
import '../models/download_record.dart';

/// 下载记录仓储契约（Hive 实现 + 内存实现，后者供单测使用）。
abstract class DownloadHistory {
  List<DownloadRecord> get records;

  Stream<List<DownloadRecord>> get stream;

  Future<void> add(DownloadRecord record);

  Future<void> update(
    String workId,
    DownloadRecord Function(DownloadRecord record) transform, {
    bool throttle = false,
  });

  Future<void> remove(String workId);

  Future<void> clearFinished();

  /// 启动时把上次进程被杀时遗留的 queued/running 标记成 failed。
  Future<int> markInterrupted();

  Future<void> dispose();
}

/// Hive 实现：单 key 存 JSON 数组，按 updatedAt 倒序，上限 200 条（对齐 JmScript）。
class HiveDownloadHistory implements DownloadHistory {
  HiveDownloadHistory(this._box);

  static const String _keyRecords = 'records';

  final Box<dynamic> _box;
  final StreamController<List<DownloadRecord>> _controller =
      StreamController<List<DownloadRecord>>.broadcast();
  List<DownloadRecord> _cache = const <DownloadRecord>[];
  DateTime _lastWrite = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  List<DownloadRecord> get records => _cache;

  @override
  Stream<List<DownloadRecord>> get stream => _controller.stream;

  /// 从 box 载入（冷启动调用一次）。
  Future<void> load() async {
    _cache = _decode(_box.get(_keyRecords) as String?);
    _emit();
  }

  @override
  Future<void> add(DownloadRecord record) async {
    final next = <DownloadRecord>[
      record,
      ..._cache.where((item) => item.workId != record.workId),
    ];
    await _persist(next);
  }

  @override
  Future<void> update(
    String workId,
    DownloadRecord Function(DownloadRecord record) transform, {
    bool throttle = false,
  }) async {
    final index = _cache.indexWhere((item) => item.workId == workId);
    if (index < 0) return;

    final current = _cache[index];
    final updated = transform(current);
    // 落盘节流：state/status 变化必写，否则 500ms 内不重复写。
    final stateChanged =
        updated.state != current.state || updated.status != current.status;
    final now = DateTime.now();
    if (throttle &&
        !stateChanged &&
        now.difference(_lastWrite) < AppConfig.historyWriteThrottle) {
      return;
    }

    final next = List<DownloadRecord>.from(_cache);
    next[index] = updated;
    await _persist(next);
  }

  @override
  Future<void> remove(String workId) async {
    await _persist(_cache.where((item) => item.workId != workId).toList());
  }

  @override
  Future<void> clearFinished() async {
    await _persist(_cache.where((item) => item.isActive).toList());
  }

  @override
  Future<int> markInterrupted() async {
    var count = 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    final next = _cache.map((record) {
      if (!record.isActive) return record;
      count++;
      return record.copyWith(
        state: DownloadState.failed,
        status: '下载失败',
        detail: '进程被系统回收',
        error: '进程被系统回收',
        updatedAt: now,
      );
    }).toList(growable: false);
    if (count > 0) {
      await _persist(next);
      Log.w('标记了 $count 个被系统回收的下载任务');
    }
    return count;
  }

  @override
  Future<void> dispose() async {
    await _controller.close();
  }

  Future<void> _persist(List<DownloadRecord> next) async {
    final sorted = List<DownloadRecord>.from(next)
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    _cache = List<DownloadRecord>.unmodifiable(
      sorted.take(AppConfig.maxDownloadRecords),
    );
    _lastWrite = DateTime.now();
    await _box.put(
      _keyRecords,
      jsonEncode(_cache.map((item) => item.toJson()).toList(growable: false)),
    );
    _emit();
  }

  void _emit() {
    if (!_controller.isClosed) _controller.add(_cache);
  }

  List<DownloadRecord> _decode(String? raw) {
    if (raw == null || raw.isEmpty) return const <DownloadRecord>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const <DownloadRecord>[];
      return decoded
          .whereType<Map>()
          .map(
            (item) => DownloadRecord.fromJson(
              item.map((key, value) => MapEntry('$key', value)),
            ),
          )
          .where((item) => item.workId.isNotEmpty && item.albumId.isNotEmpty)
          .toList(growable: false);
    } catch (error) {
      Log.e('下载记录解码失败', error);
      return const <DownloadRecord>[];
    }
  }
}

/// 内存实现（单测 / 预览用）。
class MemoryDownloadHistory implements DownloadHistory {
  MemoryDownloadHistory([List<DownloadRecord> initial = const <DownloadRecord>[]])
      : _records = List<DownloadRecord>.from(initial);

  final StreamController<List<DownloadRecord>> _controller =
      StreamController<List<DownloadRecord>>.broadcast();
  List<DownloadRecord> _records;
  DateTime _lastWrite = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  List<DownloadRecord> get records => List<DownloadRecord>.unmodifiable(_records);

  @override
  Stream<List<DownloadRecord>> get stream => _controller.stream;

  @override
  Future<void> add(DownloadRecord record) async {
    _records = <DownloadRecord>[
      record,
      ..._records.where((item) => item.workId != record.workId),
    ];
    _emit();
  }

  @override
  Future<void> update(
    String workId,
    DownloadRecord Function(DownloadRecord record) transform, {
    bool throttle = false,
  }) async {
    final index = _records.indexWhere((item) => item.workId == workId);
    if (index < 0) return;
    final current = _records[index];
    final updated = transform(current);
    final stateChanged =
        updated.state != current.state || updated.status != current.status;
    final now = DateTime.now();
    if (throttle &&
        !stateChanged &&
        now.difference(_lastWrite) < AppConfig.historyWriteThrottle) {
      return;
    }
    _records = List<DownloadRecord>.from(_records)..[index] = updated;
    _lastWrite = DateTime.now();
    _emit();
  }

  @override
  Future<void> remove(String workId) async {
    _records = _records.where((item) => item.workId != workId).toList();
    _emit();
  }

  @override
  Future<void> clearFinished() async {
    _records = _records.where((item) => item.isActive).toList();
    _emit();
  }

  @override
  Future<int> markInterrupted() async {
    var count = 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    _records = _records.map((record) {
      if (!record.isActive) return record;
      count++;
      return record.copyWith(
        state: DownloadState.failed,
        status: '下载失败',
        detail: '进程被系统回收',
        error: '进程被系统回收',
        updatedAt: now,
      );
    }).toList(growable: false);
    if (count > 0) _emit();
    return count;
  }

  @override
  Future<void> dispose() async {
    await _controller.close();
  }

  void _emit() {
    if (!_controller.isClosed) _controller.add(records);
  }
}
