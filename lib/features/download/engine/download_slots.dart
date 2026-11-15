import 'dart:async';
import 'dart:collection';

/// 队列级并发信号量（移植 `JmScript/download/DownloadSlots.kt`，上限 3）。
class DownloadSlots {
  DownloadSlots(this.maxParallel) : assert(maxParallel > 0);

  final int maxParallel;
  int _active = 0;
  final Queue<Completer<void>> _waiters = Queue<Completer<void>>();

  int get active => _active;

  Future<T> withSlot<T>(Future<T> Function() block) async {
    await _acquire();
    try {
      return await block();
    } finally {
      _release();
    }
  }

  Future<void> _acquire() {
    if (_active < maxParallel) {
      _active++;
      return Future<void>.value();
    }
    final completer = Completer<void>();
    _waiters.add(completer);
    return completer.future;
  }

  void _release() {
    if (_waiters.isNotEmpty) {
      final next = _waiters.removeFirst();
      if (!next.isCompleted) next.complete();
      return;
    }
    _active = (_active - 1).clamp(0, maxParallel).toInt();
  }
}

/// 受限并发 map：保持结果顺序，失败按 [onError] 处理。
Future<List<R>> mapWithConcurrency<T, R>(
  List<T> items,
  int maxParallel,
  Future<R> Function(T item, int index) task, {
  R Function(T item, int index, Object error)? onError,
}) async {
  final slots = DownloadSlots(maxParallel);
  final results = List<R?>.filled(items.length, null);
  await Future.wait<void>(<Future<void>>[
    for (var index = 0; index < items.length; index++)
      slots.withSlot<void>(() async {
        try {
          results[index] = await task(items[index], index);
        } catch (error) {
          if (onError == null) rethrow;
          results[index] = onError(items[index], index, error);
        }
      }),
  ]);
  return results.cast<R>();
}
