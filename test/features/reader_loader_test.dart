import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:jm_comic/features/reader/reader_page_loader.dart';

Uint8List _bytes([int seed = 1]) =>
    Uint8List.fromList(List<int>.filled(8, seed));

void main() {
  group('窗口预取', () {
    test('并发只有 2 路时，窗口内 6 页最终都会补齐（旧实现会停在第 2 页）', () async {
      final started = <int>[];
      final loader = ReaderPageLoader(
        total: 30,
        concurrency: 2,
        ahead: 5,
        behind: 2,
        fetch: (page) async {
          started.add(page);
          await Future<void>.delayed(Duration.zero);
          return _bytes(page);
        },
        onChanged: () {},
      );

      loader.setFocus(1);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(started.toSet(), <int>{1, 2, 3, 4, 5, 6});
      expect(loader.cachedCount, 6);
      expect(loader.isBusy, isFalse);
      loader.dispose();
    });

    test('优先级：当前页最先，其次向后续页推进', () async {
      final started = <int>[];
      final loader = ReaderPageLoader(
        total: 30,
        concurrency: 1,
        ahead: 3,
        behind: 1,
        fetch: (page) async {
          started.add(page);
          return _bytes(page);
        },
        onChanged: () {},
      );

      loader.setFocus(10);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      // 窗口 9..13：从当前页开始向前，回看的 9 最后。
      expect(started, <int>[10, 11, 12, 13, 9]);
      loader.dispose();
    });

    test('焦点变化后窗口滑动，旧窗口外的排队项被丢弃', () async {
      final started = <int>[];
      final loader = ReaderPageLoader(
        total: 100,
        concurrency: 1,
        ahead: 4,
        behind: 1,
        fetch: (page) async {
          started.add(page);
          await Future<void>.delayed(const Duration(milliseconds: 2));
          return _bytes(page);
        },
        onChanged: () {},
      );

      loader.setFocus(1);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      loader.setFocus(50);
      await Future<void>.delayed(const Duration(milliseconds: 40));

      expect(started, contains(50));
      expect(started, contains(54));
      // 窗口 49..54 之外的页不应该继续被加载
      expect(started.where((page) => page > 54), isEmpty);
      expect(loader.bytesOf(50), isNotNull);
      loader.dispose();
    });
  });

  group('失败与重试', () {
    test('失败页标记 failed；request 后重试成功', () async {
      var attempt = 0;
      final loader = ReaderPageLoader(
        total: 5,
        concurrency: 1,
        ahead: 0,
        behind: 0,
        fetch: (page) async {
          attempt++;
          if (attempt == 1) return null;
          return _bytes(page);
        },
        onChanged: () {},
      );

      loader.setFocus(1);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(loader.isFailed(1), isTrue);
      expect(loader.bytesOf(1), isNull);

      loader.request(1);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(loader.isFailed(1), isFalse);
      expect(loader.bytesOf(1), isNotNull);
      loader.dispose();
    });
  });

  group('缓存', () {
    test('LRU 不超过 cacheSize，且优先保留窗口内页面', () async {
      final loader = ReaderPageLoader(
        total: 40,
        concurrency: 2,
        ahead: 5,
        behind: 2,
        cacheSize: 4,
        fetch: (page) async => _bytes(page),
        onChanged: () {},
      );

      loader.setFocus(20);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(loader.cachedCount, lessThanOrEqualTo(4));
      expect(loader.bytesOf(20), isNotNull);
      loader.dispose();
    });

    test('clear 之后缓存清空并重新按焦点加载', () async {
      var calls = 0;
      final loader = ReaderPageLoader(
        total: 10,
        concurrency: 2,
        ahead: 2,
        behind: 0,
        fetch: (page) async {
          calls++;
          return _bytes(page);
        },
        onChanged: () {},
      );

      loader.setFocus(3);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final before = calls;
      expect(loader.cachedCount, greaterThan(0));

      loader.clear();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(calls, greaterThan(before));
      expect(loader.bytesOf(3), isNotNull);
      loader.dispose();
    });
  });

  group('生命周期', () {
    test('dispose 之后继续返回的请求不会污染状态', () async {
      final completer = Completer<Uint8List?>();
      var notified = 0;
      final loader = ReaderPageLoader(
        total: 3,
        concurrency: 1,
        ahead: 1,
        behind: 0,
        fetch: (page) => completer.future,
        onChanged: () => notified++,
      );

      loader.setFocus(1);
      loader.dispose();
      completer.complete(_bytes());
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(notified, 0);
      expect(loader.cachedCount, 0);
    });
  });
}
