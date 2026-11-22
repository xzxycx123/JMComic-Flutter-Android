import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';

import '../../core/config/app_config.dart';
import '../../core/utils/logger.dart';

/// 阅读器页面加载调度器（窗口预取 + 并发闸门 + 失败重试）。
///
/// 旧实现是「在 build/翻页时顺手发起 [readerPreloadRadius] 范围内的加载，并发满了就直接 return」，
/// 被 return 掉的那几页永远没人再管 —— 表现就是进入阅读器后图片一张一张冒出来，其余一直是转圈。
/// 这里改成真正的队列：窗口内所有页都进队列，并发槽位腾出来就自动补位，直到窗口填满。
class ReaderPageLoader {
  ReaderPageLoader({
    required this.total,
    required this.fetch,
    required this.onChanged,
    this.concurrency = AppConfig.readerFetchConcurrency,
    this.ahead = AppConfig.readerPreloadAhead,
    this.behind = AppConfig.readerPreloadBehind,
    this.cacheSize = AppConfig.readerCacheSize,
  });

  /// 章节总页数。
  final int total;

  /// 单页加载（下载 + 切片还原），失败返回 null。
  final Future<Uint8List?> Function(int page) fetch;

  /// 任意状态变化回调（用于 setState 刷新页面）。
  final VoidCallback onChanged;

  final int concurrency;
  final int ahead;
  final int behind;
  final int cacheSize;

  final Map<int, Uint8List> _bytes = <int, Uint8List>{};
  final List<int> _lru = <int>[];
  final Set<int> _failed = <int>{};
  final Set<int> _inFlight = <int>{};
  final Set<int> _queued = <int>{};

  int _focus = 1;
  int _generation = 0;
  bool _disposed = false;

  int get focus => _focus;
  int get cachedCount => _bytes.length;
  int get failedCount => _failed.length;
  int get pendingCount => _queued.length + _inFlight.length;
  bool get isBusy => pendingCount > 0;

  Uint8List? bytesOf(int page) => _bytes[page];

  /// 当前已解码页的快照（结束页导出用）。
  ///
  /// 导出可能比 LRU 存活更久：先把此刻命中的页复制一份，之后即使被 [evict] 淘汰，
  /// 导出仍能复用这些字节，只有真正没加载过的页才回落到网络。
  Map<int, Uint8List> snapshot() => Map<int, Uint8List>.of(_bytes);

  bool isFailed(int page) => _failed.contains(page);

  bool isLoading(int page) =>
      _inFlight.contains(page) || _queued.contains(page);

  /// 当前焦点页变化：窗口滑动 + 触发补位。
  void setFocus(int page) {
    if (_disposed) return;
    final next = total <= 0 ? 1 : page.clamp(1, total).toInt();
    _focus = next;
    _enqueueWindow();
    _pump();
  }

  /// 单页重试 / 插队（失败重试按钮、刚跳到很远的一页）。
  void request(int page) {
    if (_disposed || total <= 0) return;
    final target = page.clamp(1, total).toInt();
    if (_bytes.containsKey(target)) return;
    _failed.remove(target);
    if (_inFlight.contains(target)) return;
    _queued.add(target);
    _pump();
  }

  /// 切换分流后清空（旧线路的字节全部作废），按当前焦点重新排队。
  void clear() {
    if (_disposed) return;
    _generation++;
    _bytes.clear();
    _lru.clear();
    _failed.clear();
    _inFlight.clear();
    _queued.clear();
    onChanged();
    _enqueueWindow();
    _pump();
  }

  void dispose() {
    _disposed = true;
    _generation++;
    _bytes.clear();
    _lru.clear();
    _failed.clear();
    _inFlight.clear();
    _queued.clear();
  }

  // ---------------------------------------------------------------- 内部
  void _enqueueWindow() {
    final start = math.max(1, _focus - behind);
    final end = math.min(total, _focus + ahead);
    // 窗口外的排队项直接丢弃：用户已经翻走，没必要继续占并发。
    _queued.removeWhere((page) => page < start || page > end);
    for (var page = start; page <= end; page++) {
      if (_bytes.containsKey(page)) continue;
      if (_failed.contains(page)) continue;
      if (_inFlight.contains(page)) continue;
      _queued.add(page);
    }
  }

  /// 前向优先（下一张最急），回看不急；同优先级按页码升序。
  int _priority(int page) =>
      page >= _focus ? page - _focus : 100 + (_focus - page);

  void _pump() {
    if (_disposed) return;
    while (_inFlight.length < concurrency && _queued.isNotEmpty) {
      final page =
          _queued.reduce((a, b) => _priority(a) <= _priority(b) ? a : b);
      _queued.remove(page);
      _start(page);
    }
  }

  void _start(int page) {
    _inFlight.add(page);
    unawaited(_run(page, _generation));
  }

  Future<void> _run(int page, int generation) async {
    Uint8List? bytes;
    try {
      bytes = await fetch(page);
    } catch (error) {
      Log.w('阅读器第 $page 页加载异常：$error');
      bytes = null;
    }
    // 已 dispose 或已切换分流：结果作废，但不能污染新一批状态。
    if (_disposed || generation != _generation) return;

    _inFlight.remove(page);
    if (bytes == null || bytes.isEmpty) {
      _failed.add(page);
    } else {
      _bytes[page] = bytes;
      _failed.remove(page);
      _touch(page);
      _evict();
    }
    onChanged();
    _pump();
  }

  void _touch(int page) {
    _lru.remove(page);
    _lru.add(page);
  }

  void _evict() {
    if (_bytes.length <= cacheSize) return;
    final keepFrom = math.max(1, _focus - behind);
    final keepTo = math.min(total, _focus + ahead);

    // 1) 先清窗口外的页（用户已经翻走的方向）。
    for (final page in List<int>.of(_lru)) {
      if (_bytes.length <= cacheSize) break;
      if (page >= keepFrom && page <= keepTo) continue;
      _drop(page);
    }

    // 2) 窗口本身比缓存还大时，按「离焦点越远越先丢」继续压，焦点页永不丢。
    if (_bytes.length > cacheSize) {
      final candidates = _lru
          .where((page) => page != _focus)
          .toList(growable: true)
        ..sort((a, b) => _distance(b).compareTo(_distance(a)));
      for (final page in candidates) {
        if (_bytes.length <= cacheSize) break;
        _drop(page);
      }
    }
  }

  int _distance(int page) => (page - _focus).abs();

  void _drop(int page) {
    _lru.remove(page);
    _bytes.remove(page);
  }
}
