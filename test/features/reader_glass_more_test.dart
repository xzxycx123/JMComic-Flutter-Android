import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_ce/hive.dart';
import 'package:jm_comic/core/di/providers.dart';
import 'package:jm_comic/core/icons/app_icons.dart';
import 'package:jm_comic/core/theme/app_colors.dart';
import 'package:jm_comic/core/ui/glass/app_glass.dart';
import 'package:jm_comic/data/local/hive_init.dart';
import 'package:jm_comic/data/local/progress_store.dart';
import 'package:jm_comic/data/local/settings_store.dart';
import 'package:jm_comic/data/models/jm_chapter.dart';
import 'package:jm_comic/data/repositories/album_repository.dart';
import 'package:jm_comic/data/sources/jm_api_client.dart';
import 'package:jm_comic/features/reader/reader_image_saver.dart';
import 'package:jm_comic/features/reader/reader_mode.dart';
import 'package:jm_comic/features/reader/reader_page.dart';
import 'package:jm_comic/features/reader/reader_providers.dart';
import 'package:jm_comic/features/reader/widgets/reader_tap_zones.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../helpers/fixtures.dart';
import '../helpers/test_env.dart';

const ReaderArgs _readerArgs = ReaderArgs(
  albumId: '7000',
  chapterId: '7999',
  title: '第 1 话',
  albumTitle: '测试本',
);

ReaderData _readerData({ReaderMode mode = ReaderMode.paged}) => ReaderData(
      args: _readerArgs,
      chapter: const JmChapter(
        id: '7999',
        title: '第 1 话',
        images: <String>['001.webp', '002.webp', '003.webp'],
      ),
      scrambleId: 220980,
      initialPage: 1,
      mode: mode,
    );

class _StubReaderController extends ReaderController {
  _StubReaderController(this.data);

  final ReaderData data;

  @override
  Future<ReaderData> build(ReaderArgs arg) async => data;
}

/// 页面字节固定失败（不跑图片解码），只关心菜单 / 分流行为。
class _StubAlbumRepository extends AlbumRepository {
  _StubAlbumRepository(JmApi api, ProgressStore store, {this.bytes})
      : super(api: api, progress: store);

  final Uint8List? bytes;

  @override
  Future<Uint8List?> loadPage({
    required String photoId,
    required String filename,
    int? scrambleIdOverride,
  }) async =>
      bytes;
}

/// 记录 switchApiHost 的分流桩；给 [holdSwitch] 时切线路挂起，用来观察「切换中」。
class _CountingJmApi extends FakeJmApi {
  final List<String> switches = <String>[];

  /// 非空时 switchApiHost 等待它完成（验证 `_switchingLine` 的禁用/恢复）。
  Completer<bool>? holdSwitch;

  @override
  Future<bool> switchApiHost(String host) async {
    switches.add(host);
    final pending = holdSwitch;
    if (pending != null) return pending.future;
    return true;
  }
}

class _MemoryProgressStore extends ProgressStore {
  _MemoryProgressStore(super.box);

  final Map<String, ReaderProgress> _values = <String, ReaderProgress>{};

  @override
  ReaderProgress? read(String albumId, String chapterId) =>
      _values[ProgressStore.keyFor(albumId, chapterId)];

  @override
  Future<void> write(
    String albumId,
    String chapterId,
    ReaderProgress progress,
  ) async {
    _values[ProgressStore.keyFor(albumId, chapterId)] = progress;
    notifyChanged();
  }
}

class _MemorySettingsStore extends SettingsStore {
  _MemorySettingsStore(super.box);

  AppSettings _value = const AppSettings();

  @override
  AppSettings read() => _value;

  @override
  Future<void> write(AppSettings settings) async => _value = settings;
}

/// 慢落盘 store：模拟「退出时 await 落盘」的窗口期（重入闸门测试用）。
class _SlowProgressStore extends _MemoryProgressStore {
  _SlowProgressStore(super.box, this.writeDelay);

  final Duration writeDelay;

  @override
  Future<void> write(
    String albumId,
    String chapterId,
    ReaderProgress progress,
  ) async {
    await Future<void>.delayed(writeDelay);
    await super.write(albumId, chapterId, progress);
  }
}

class _GlassHarness {
  _GlassHarness({
    required this.api,
    required this.store,
    required this.container,
  });

  final _CountingJmApi api;
  final ProgressStore store;
  final ProviderContainer container;

  ReaderProgress? read([String chapterId = '7999']) =>
      store.read('7000', chapterId);
}

/// 玻璃皮肤 + 浅色 App 主题的阅读器（菜单挂在根 Overlay，必须验证浅色主题下仍可读）。
Future<_GlassHarness> _pumpGlassReader(
  WidgetTester tester, {
  ReaderMode mode = ReaderMode.paged,
  ReaderImageSaver? imageSaver,
  _CountingJmApi? api,
  Uint8List? pageBytes,
  Duration? writeDelay,
  Size? logicalSize,
  double textScale = 1,
  List<String>? systemUiCalls,
}) async {
  if (logicalSize != null) {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = logicalSize * 3;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
  }
  if (systemUiCalls != null) {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'SystemChrome.setEnabledSystemUIMode') {
          systemUiCalls.add('${call.arguments}');
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );
  }

  final counting = api ?? _CountingJmApi();
  final box = Hive.box<dynamic>(HiveBoxes.readerProgress);
  final store = writeDelay == null
      ? _MemoryProgressStore(box)
      : _SlowProgressStore(box, writeDelay);
  final container = ProviderContainer(
    overrides: <Override>[
      sharedPreferencesProvider.overrideWithValue(await testPreferences()),
      settingsStoreProvider.overrideWithValue(
        _MemorySettingsStore(Hive.box<dynamic>(HiveBoxes.settings)),
      ),
      jmApiProvider.overrideWithValue(counting),
      progressStoreProvider.overrideWithValue(store),
      if (imageSaver != null)
        readerImageSaverProvider.overrideWithValue(imageSaver),
      albumRepositoryProvider.overrideWith(
        (ref) async => _StubAlbumRepository(counting, store, bytes: pageBytes),
      ),
      readerDataProvider
          .overrideWith(() => _StubReaderController(_readerData(mode: mode))),
    ],
  );
  late final GoRouter router;
  router = GoRouter(
    initialLocation: '/home',
    routes: <RouteBase>[
      GoRoute(
        path: '/home',
        builder: (context, state) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => router.push('/reader'),
              child: const Text('打开阅读器'),
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/reader',
        builder: (context, state) => const ReaderPage(args: _readerArgs),
      ),
    ],
  );
  addTearDown(() {
    router.dispose();
    container.dispose();
  });

  await tester.pumpWidget(
    LiquidGlassWidgets.wrap(
      brightnessResolver: Theme.maybeBrightnessOf,
      child: UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          theme: ThemeData.light(),
          routerConfig: router,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(textScale),
            ),
            child: InterfaceStyleScope(
              style: AppInterfaceStyle.liquidGlass,
              child: child ?? const SizedBox.shrink(),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('打开阅读器'));
  await tester.pumpAndSettle();
  return _GlassHarness(api: counting, store: store, container: container);
}

Future<void> _openMore(WidgetTester tester) async {
  expect(find.byType(GlassPullDownButton), findsOneWidget);
  await tester.tap(find.byType(GlassPullDownButton));
  await tester.pumpAndSettle();
}

/// 点菜单外面关掉气泡（barrier），留出收起动画。
Future<void> _dismissMenu(WidgetTester tester) async {
  final size = tester.getSize(find.byType(ReaderTapZones));
  await tester.tapAt(Offset(size.width * .5, size.height * .5));
  await tester.pumpAndSettle();
}

/// 点右侧 1/3 翻到下一页（不带 pumpAndSettle，方便控制时间）。
Future<void> _tapNext(WidgetTester tester) async {
  final rect = tester.getRect(find.byType(ReaderTapZones));
  await tester.tapAt(Offset(rect.left + rect.width * .9, rect.center.dy));
  await tester.pump(const Duration(milliseconds: 320));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initTestStores();
  });

  setUp(() async {
    await clearTestBoxes();
  });

  testWidgets('玻璃更多：二级气泡含三项，「选择节点」原生展开唯一三级气泡', (tester) async {
    await _pumpGlassReader(tester);

    // Metal 的 AppSheet 路径不出现：顶栏用 GlassPullDownButton。
    expect(
      find.byType(AppIconButton),
      findsOneWidget,
      reason: '只剩「返回」一个普通图标按钮',
    );

    await _openMore(tester);
    expect(find.text('翻页方式'), findsOneWidget);
    // 单行菜单：当前模式换成右侧「切换到…」提示，和标题同一条中线。
    expect(find.textContaining('切换到'), findsOneWidget);
    expect(find.text('选择节点'), findsOneWidget);
    expect(find.text('下载当页图片'), findsOneWidget);
    expect(find.byType(GlassMenu), findsOneWidget, reason: '二级菜单只有一个气泡');

    // 选择节点 → 原生子菜单卡片（GlassMenuItem.submenu），不另开第二个菜单。
    await tester.tap(find.text('选择节点'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('glass-menu-header-1')),
      findsOneWidget,
      reason: '三级卡片的 header 只出现一次',
    );
    expect(find.byType(GlassMenu), findsOneWidget, reason: '没有第二个 GlassMenu');
    expect(find.text('选择节点'), findsNWidgets(2), reason: '父行 + 三级卡片 header');
    expect(find.text('线路1'), findsOneWidget);
    expect(find.text('线路2'), findsOneWidget);

    // 三级卡片里再点 header 收回去，二级菜单还在。
    await tester.tap(find.byKey(const ValueKey<String>('glass-menu-header-1')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('glass-menu-header-1')),
      findsNothing,
    );
    expect(find.text('下载当页图片'), findsOneWidget);

    await _dismissMenu(tester);
    expect(find.text('翻页方式'), findsNothing);
    unawaited(tester.binding.handlePopRoute());
    await tester.pumpAndSettle();
  });

  testWidgets('玻璃更多：二级气泡里有翻页动画开关，切换后写回设置', (tester) async {
    final harness = await _pumpGlassReader(tester);
    await _openMore(tester);

    final toggle = find.byType(AppSwitch);
    expect(find.text('翻页动画'), findsOneWidget);
    expect(toggle, findsOneWidget, reason: '菜单里只有一个开关');
    expect(tester.widget<AppSwitch>(toggle).value, isTrue, reason: '默认开启');

    await tester.tap(toggle);
    await tester.pumpAndSettle();

    expect(
      harness.container.read(settingsProvider).pageTurnAnimation,
      isFalse,
      reason: '切开关写回 settingsProvider（和「我的 - 翻页动画」同一项）',
    );
    expect(find.text('选择节点'), findsOneWidget, reason: '切开关不会关菜单');
    expect(tester.widget<AppSwitch>(toggle).value, isFalse);

    await _dismissMenu(tester);
    await tester.pump(const Duration(seconds: 4));
    unawaited(tester.binding.handlePopRoute());
    await tester.pumpAndSettle();
  });

  testWidgets('玻璃更多：选线路直接 _applyLine，动作只执行一次，当前线路带勾', (tester) async {
    final api = (await _pumpGlassReader(tester)).api;

    await _openMore(tester);
    await tester.tap(find.text('选择节点'));
    await tester.pumpAndSettle();

    final current = tester.widget<GlassMenuItem>(
      find.byKey(const ValueKey<String>('glass-node-www.cdnbtd.cc')),
    );
    expect(current.semanticsSelected, isTrue);
    expect(current.enabled, isTrue);
    final check = current.trailing;
    expect(
      check is SvgIcon && check.asset == AppIcons.check,
      isTrue,
      reason: '当前线路打勾',
    );

    await tester.tap(find.text('线路2'));
    await tester.pumpAndSettle();
    expect(api.switches, <String>['www.cdnutc.cc'], reason: 'onTap 只跑一次，不双执行');
    expect(find.text('翻页方式'), findsNothing, reason: '选中后菜单收起');
    expect(find.textContaining('已切到 线路2'), findsOneWidget);

    // 等 toast 自己的计时器跑完再退出。
    await tester.pump(const Duration(seconds: 4));
    await tester.pump(const Duration(milliseconds: 300));
    unawaited(tester.binding.handlePopRoute());
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('玻璃更多：切线路中三级菜单整列禁用，完成后恢复', (tester) async {
    final api = _CountingJmApi()..holdSwitch = Completer<bool>();
    await _pumpGlassReader(tester, api: api);

    await _openMore(tester);
    await tester.tap(find.text('选择节点'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('线路2'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    expect(api.switches, <String>['www.cdnutc.cc']);
    expect(api.holdSwitch!.isCompleted, isFalse, reason: '切线路还挂起着');

    // 切换中重新打开三级菜单：整列禁用。
    await _openMore(tester);
    await tester.tap(find.text('选择节点'));
    await tester.pumpAndSettle();
    for (final host in const <String>[
      'www.cdnbtd.cc',
      'www.cdnutc.cc',
      'www.cdngwc.net',
      'www.cdngwc.club',
    ]) {
      final item = tester.widget<GlassMenuItem>(
        find.byKey(ValueKey<String>('glass-node-$host')),
      );
      expect(item.enabled, isFalse, reason: '$host 在切换中必须禁用');
    }

    api.holdSwitch!.complete(true);
    await tester.pumpAndSettle();
    await _dismissMenu(tester);

    await _openMore(tester);
    await tester.tap(find.text('选择节点'));
    await tester.pumpAndSettle();
    final restored = tester.widget<GlassMenuItem>(
      find.byKey(const ValueKey<String>('glass-node-www.cdngwc.net')),
    );
    expect(restored.enabled, isTrue, reason: '切换完成 / 失败后恢复可用');

    await _dismissMenu(tester);
    await tester.pump(const Duration(seconds: 4));
    await tester.pump(const Duration(milliseconds: 300));
    unawaited(tester.binding.handlePopRoute());
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('玻璃更多：菜单打开越过 HUD 3 秒自动隐藏仍存活，关闭后计时恢复', (tester) async {
    await _pumpGlassReader(tester);
    await _openMore(tester);

    // 越过 HUD 的 3 秒自动隐藏：菜单和它的 trigger 都不能被卸载。
    await tester.pump(const Duration(seconds: 4));
    expect(find.text('翻页方式'), findsOneWidget, reason: '菜单没有被 HUD 定时器拆掉');
    expect(find.byType(GlassPullDownButton), findsOneWidget);

    await _dismissMenu(tester);
    expect(find.text('翻页方式'), findsNothing);

    // 关闭后 3 秒计时恢复：HUD 自动隐藏。
    await tester.pump(const Duration(seconds: 4));
    await tester.pump(const Duration(milliseconds: 200));
    expect(
      find.byType(GlassPullDownButton),
      findsNothing,
      reason: 'HUD 重新开始自动隐藏',
    );

    unawaited(tester.binding.handlePopRoute());
    await tester.pumpAndSettle();
  });

  testWidgets('玻璃更多：返回键先收菜单，再按才退出阅读器', (tester) async {
    await _pumpGlassReader(tester);
    await _openMore(tester);

    final pop = tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await pop;
    expect(find.text('翻页方式'), findsNothing, reason: '第一下只关菜单');
    expect(find.byType(ReaderTapZones), findsOneWidget, reason: '还在阅读器里');

    final exit = tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await exit;
    expect(find.byType(ReaderTapZones), findsNothing);
    expect(find.text('打开阅读器'), findsOneWidget);
  });

  testWidgets('阅读器整页声明浅色状态栏图标，HUD 显隐都不变', (tester) async {
    await _pumpGlassReader(tester);

    AnnotatedRegion<SystemUiOverlayStyle> region() => tester.widget(
          find.ancestor(
            of: find.byType(Scaffold),
            matching: find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
          ),
        );
    expect(
      region().value.statusBarIconBrightness,
      Brightness.light,
      reason: '深色阅读器上状态栏图标必须是浅色',
    );
    expect(
      find.ancestor(
        of: find.byType(ReaderTapZones),
        matching: find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
      ),
      findsOneWidget,
      reason: '声明挂在阅读器整页上，不只在 HUD 子树里',
    );

    // 收起 HUD 后声明依旧在（不是靠 HUD 短暂声明图标明暗）。
    final rect = tester.getRect(find.byType(ReaderTapZones));
    await tester.tapAt(rect.center);
    await tester.pump(const Duration(milliseconds: 250));
    expect(
      find.ancestor(
        of: find.byType(Scaffold),
        matching: find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
      ),
      findsOneWidget,
    );
    expect(region().value.statusBarBrightness, Brightness.dark);

    await tester.pump(const Duration(seconds: 4));
    unawaited(tester.binding.handlePopRoute());
    await tester.pumpAndSettle();
  });

  testWidgets('玻璃更多：浅色 App 主题下菜单仍是可读的深色阅读器菜单', (tester) async {
    await _pumpGlassReader(tester);
    await _openMore(tester);

    final label = find.text('翻页方式');
    // App 主题是浅色，菜单仍是深色阅读器皮肤：文字 / 图标颜色写死成墨色。
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).theme?.brightness,
      Brightness.light,
    );
    expect(
      Theme.of(tester.element(label)).brightness,
      Brightness.dark,
      reason: '菜单沿用阅读器深色皮肤',
    );
    expect(
      tester.widget<Text>(label).style?.color,
      AppColors.readerInk,
      reason: '文字颜色必须写死成阅读器墨色',
    );
    final trigger =
        tester.widget<GlassPullDownButton>(find.byType(GlassPullDownButton));
    expect(
      trigger.quality,
      GlassQuality.premium,
      reason: 'overlay 用 premium 气泡',
    );
    expect(trigger.settings, isNotNull);
    expect(trigger.onSelected, isNull, reason: '业务动作挂在 item.onTap，不双执行');

    await _dismissMenu(tester);
    unawaited(tester.binding.handlePopRoute());
    await tester.pumpAndSettle();
  });

  testWidgets('落盘没完成时连续两次返回也只退出一次，并且最终页落盘', (tester) async {
    final harness = await _pumpGlassReader(
      tester,
      writeDelay: const Duration(milliseconds: 300),
    );
    await _tapNext(tester); // -> 第 2 页
    expect(harness.read()?.page, 2);

    final first = tester.binding.handlePopRoute();
    await tester.pump(const Duration(milliseconds: 50)); // _exit 还卡在落盘 await
    final second = tester.binding.handlePopRoute();
    await tester.pump(const Duration(milliseconds: 400)); // 落盘完成 → 只弹一次栈
    await tester.pumpAndSettle();
    await first;
    await second;

    expect(find.byType(ReaderTapZones), findsNothing, reason: '退出阅读器');
    expect(
      find.text('打开阅读器'),
      findsOneWidget,
      reason: '第二次返回被闸门吃掉，没有把上一页也弹掉',
    );
    expect(harness.read()?.page, 2, reason: '退出前的最终页已落盘');

    // 退出路径（didPop / dispose）还会各排一次落盘，把慢写的定时器跑完。
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('收起动画期间再次返回：直接退出阅读器', (tester) async {
    await _pumpGlassReader(tester);
    await _openMore(tester);

    final closeMenu = tester.binding.handlePopRoute();
    await tester.pump(const Duration(milliseconds: 80)); // 收起动画仍在跑
    final exitReader = tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await closeMenu;
    await exitReader;

    expect(find.text('翻页方式'), findsNothing);
    expect(find.byType(ReaderTapZones), findsNothing, reason: '第二次返回直接退出');
    expect(find.text('打开阅读器'), findsOneWidget);
  });

  testWidgets('首帧就显示系统状态栏，HUD 隐藏才进沉浸，恢复 HUD 再回 edgeToEdge', (tester) async {
    final systemUi = <String>[];
    await _pumpGlassReader(tester, systemUiCalls: systemUi);

    expect(
      systemUi,
      isNotEmpty,
      reason: 'ReaderPage 必须显式设置 SystemUiMode',
    );
    expect(
      systemUi.where((call) => call.contains('immersiveSticky')),
      isEmpty,
      reason: 'HUD 可见时不能进沉浸模式（否则顶部会是 28px 幻影空带）',
    );
    expect(systemUi.last, 'SystemUiMode.edgeToEdge');

    await tester.pump(const Duration(seconds: 4)); // HUD 自动隐藏
    await tester.pump(const Duration(milliseconds: 200));
    expect(systemUi.last, 'SystemUiMode.immersiveSticky');

    final zones = tester.getRect(find.byType(ReaderTapZones));
    await tester.tapAt(zones.center); // 点中间重新唤出 HUD
    await tester.pump(const Duration(milliseconds: 300));
    expect(systemUi.last, 'SystemUiMode.edgeToEdge');

    await tester.pump(const Duration(seconds: 4));
    unawaited(tester.binding.handlePopRoute());
    await tester.pumpAndSettle();
  });

  testWidgets('点菜单外面关掉气泡后 HUD/trigger 还在，那一下 tap 不会切换 HUD', (tester) async {
    await _pumpGlassReader(tester);
    await _openMore(tester);

    final zones = tester.getRect(find.byType(ReaderTapZones));
    await tester.tapAt(zones.center); // barrier 吃掉这一下
    await tester.pump(const Duration(milliseconds: 120));

    expect(
      find.byType(GlassPullDownButton),
      findsOneWidget,
      reason: '收起动画开始后 HUD 不能被拆掉',
    );
    expect(
      find.textContaining('第 1/3 页'),
      findsOneWidget,
      reason: '那一下 tap 被 barrier 吃掉，没有切换 HUD',
    );
    await tester.pumpAndSettle();
    expect(find.text('翻页方式'), findsNothing, reason: '收起动画结束后菜单消失');

    await tester.pump(const Duration(seconds: 4)); // 计时器恢复后自动隐藏
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(GlassPullDownButton), findsNothing);
    unawaited(tester.binding.handlePopRoute());
    await tester.pumpAndSettle();
  });

  testWidgets('三级展开时 root 的「下载当页图片」inert，点了不会落盘', (tester) async {
    final saver = MemoryReaderImageSaver();
    await _pumpGlassReader(
      tester,
      imageSaver: saver,
      pageBytes: syntheticPng(),
    );
    await _openMore(tester);
    await tester.tap(find.text('选择节点'));
    await tester.pumpAndSettle();

    final rootDownload = find.text('下载当页图片');
    expect(rootDownload, findsOneWidget);
    expect(
      find.ancestor(of: rootDownload, matching: find.byType(IgnorePointer)),
      findsWidgets,
      reason: '被三级卡片盖住的 root 层应该是 inert 的',
    );

    await tester.tap(rootDownload, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(saver.files, isEmpty, reason: 'root 下载项不执行');
    expect(find.textContaining('已保存'), findsNothing);

    await _dismissMenu(tester);
    await tester.pump(const Duration(seconds: 4));
    unawaited(tester.binding.handlePopRoute());
    await tester.pumpAndSettle();
  });

  testWidgets('320x640 + 1.3 倍字号：二级 / 三级都不出屏、没有 overflow', (tester) async {
    const screen = Rect.fromLTWH(0, 0, 320, 640);
    await _pumpGlassReader(
      tester,
      logicalSize: const Size(320, 640),
      textScale: 1.3,
    );

    await _openMore(tester);
    expect(tester.takeException(), isNull);
    for (final label in <String>['翻页方式', '翻页动画', '选择节点', '下载当页图片']) {
      expect(
        screen.contains(tester.getRect(find.text(label)).center),
        isTrue,
        reason: '$label 必须完整落在屏幕里',
      );
    }

    await tester.tap(find.text('选择节点'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      screen.contains(tester.getRect(find.text('线路1')).center),
      isTrue,
    );

    await _dismissMenu(tester);
    await tester.pump(const Duration(seconds: 4));
    unawaited(tester.binding.handlePopRoute());
    await tester.pumpAndSettle();
  });

  testWidgets('reduceMotion 时 trigger 用 MorphSpeed.instant', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

    await _pumpGlassReader(tester);
    final trigger =
        tester.widget<GlassPullDownButton>(find.byType(GlassPullDownButton));
    expect(trigger.morphSpeed, MorphSpeed.instant);

    await tester.pump(const Duration(seconds: 4));
    unawaited(tester.binding.handlePopRoute());
    await tester.pumpAndSettle();
  });

  testWidgets('三级卡片打开时父级 items 重建（_switchingLine 变化）会刷新 disabled',
      (tester) async {
    var switching = false;
    late StateSetter rebuild;
    await tester.pumpWidget(
      LiquidGlassWidgets.wrap(
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: StatefulBuilder(
                builder: (context, setState) {
                  rebuild = setState;
                  return GlassPullDownButton(
                    icon: const SvgIcon(AppIcons.more, size: 16),
                    buttonWidth: 34,
                    buttonHeight: 34,
                    items: <Widget>[
                      GlassMenuItem(
                        title: '选择节点',
                        onTap: () {},
                        submenu: <Widget>[
                          GlassMenuItem(
                            key: const ValueKey<String>('probe-node'),
                            title: '线路1',
                            enabled: !switching,
                            onTap: () {},
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(GlassPullDownButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('选择节点'));
    await tester.pumpAndSettle();

    final probe = find.byKey(const ValueKey<String>('probe-node'));
    expect(tester.widget<GlassMenuItem>(probe).enabled, isTrue);

    // 卡片开着时父级重建（ReaderPage 的 setState 也会这样重建 items）。
    rebuild(() => switching = true);
    await tester.pump();
    expect(
      tester.widget<GlassMenuItem>(probe).enabled,
      isFalse,
      reason: '三级卡片要跟着新的 items 刷新 disabled',
    );
  });
}
