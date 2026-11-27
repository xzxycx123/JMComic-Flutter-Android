import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../../core/config/app_config.dart';
import '../../core/constants/jm_constants.dart';
import '../../core/di/providers.dart';
import '../../core/icons/app_icons.dart';
import '../../core/icons/app_images.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/ui/app_toast.dart';
import '../../core/ui/glass/app_glass.dart';
import '../../core/utils/file_names.dart';
import '../../data/local/endpoint_store.dart';
import '../../data/local/progress_store.dart';
import '../../data/local/settings_store.dart';
import '../../data/repositories/album_repository.dart';
import '../download/engine/reader_export_worker.dart';
import 'reader_mode.dart';
import 'reader_page_loader.dart';
import 'reader_providers.dart';
import 'widgets/page_turn_view.dart';
import 'widgets/reader_end_page.dart';
import 'widgets/reader_hud.dart';
import 'widgets/reader_tap_zones.dart';
import 'widgets/scroll_reader_view.dart';

/// 阅读器整页都是深色底：不管 HUD 显不显示，系统状态栏都用浅色图标。
///
/// 挂在 [ReaderPage] 整棵子树外层（而不是 HUD 子树），HUD 隐藏 / 菜单开合都
/// 不会让状态栏图标变成深色看不见。
const SystemUiOverlayStyle readerSystemUiStyle = SystemUiOverlayStyle(
  statusBarColor: Color(0x00000000),
  statusBarIconBrightness: Brightness.light,
  statusBarBrightness: Brightness.dark,
  systemNavigationBarColor: AppColors.readerBg,
  systemNavigationBarIconBrightness: Brightness.light,
  systemNavigationBarDividerColor: Color(0x00000000),
);

/// 阅读器：双模式（左右翻页 / 上下滚动）+ 三分区点击 + HUD + 进度记忆。
class ReaderPage extends ConsumerWidget {
  const ReaderPage({required this.args, super.key});

  final ReaderArgs args;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(readerDataProvider(args));
    return ReaderPageFrame(
      child: data.when(
        loading: ReaderPageLoading.new,
        error: (error, stackTrace) => ReaderPageError(
          message: '$error',
          onRetry: () => ref.invalidate(readerDataProvider(args)),
          onExit: () => _safePop(context),
        ),
        data: (value) => ReaderView(
          title: value.title,
          total: value.total,
          initialPage: value.initialPage,
          mode: value.mode,
          onlineData: value,
          onExit: () => _safePop(context),
        ),
      ),
    );
  }
}

class ReaderPageFrame extends StatelessWidget {
  const ReaderPageFrame({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: readerSystemUiStyle,
        child: Scaffold(
          backgroundColor: AppColors.readerBg,
          body: ReaderControlsTheme(child: child),
        ),
      );
}

class ReaderPageLoading extends StatelessWidget {
  const ReaderPageLoading({super.key});

  @override
  Widget build(BuildContext context) => Center(
        child: AppSurface(
          kind: AppSurfaceKind.controlGroup,
          padding: const EdgeInsets.all(10),
          borderRadius: BorderRadius.circular(16),
          metalDecoration: BoxDecoration(
            color: AppColors.darkSurfaceContainer,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.darkOutline),
          ),
          child: const MascotLoading(compact: true, size: 72),
        ),
      );
}

void _safePop(BuildContext context) {
  if (context.canPop()) {
    context.pop();
  } else {
    context.go('/');
  }
}

class ReaderPageError extends StatelessWidget {
  const ReaderPageError({
    required this.message,
    required this.onRetry,
    required this.onExit,
    this.onOpenExternally,
    super.key,
  });

  final String message;
  final VoidCallback onRetry;
  final VoidCallback onExit;
  final VoidCallback? onOpenExternally;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: <Widget>[
          Align(
            alignment: Alignment.centerLeft,
            child: AppIconButton(
              onPressed: onExit,
              icon: const IconTheme(
                data: IconThemeData(color: AppColors.readerInk),
                child: SvgIcon(AppIcons.back, size: 22),
              ),
            ),
          ),
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const IconTheme(
                      data: IconThemeData(color: AppColors.readerInk),
                      child: SvgIcon(AppIcons.alert, size: 28),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      '加载失败',
                      style: AppTypography.sectionTitle
                          .copyWith(color: AppColors.readerInk),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      message,
                      textAlign: TextAlign.center,
                      style: AppTypography.caption.copyWith(
                        color: AppColors.readerInk.withValues(alpha: 0.7),
                      ),
                    ),
                    const SizedBox(height: 18),
                    // 药丸形（全圆角）主按钮，和 LiquidGlass 一侧的胶囊一致。
                    AppButton(
                      onPressed: onRetry,
                      cornerRadius: AppColors.radiusPill,
                      child: const Text('重试'),
                    ),
                    if (onOpenExternally != null) ...[
                      const SizedBox(height: 10),
                      AppButton.text(
                        onPressed: onOpenExternally,
                        child: const Text('用其它应用打开'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 共享的阅读界面。在线章节提供 [onlineData]，本地文档提供 [loadPage]。
class ReaderView extends ConsumerStatefulWidget {
  const ReaderView({
    required this.title,
    required this.total,
    required this.initialPage,
    required this.mode,
    required this.onExit,
    this.onlineData,
    this.loadPage,
    this.onProgress,
    super.key,
  }) : assert((onlineData != null) != (loadPage != null));

  final String title;
  final int total;
  final int initialPage;
  final ReaderMode mode;
  final VoidCallback onExit;
  final ReaderData? onlineData;
  final Future<Uint8List?> Function(int page)? loadPage;
  final Future<void> Function(int page)? onProgress;

  @override
  ConsumerState<ReaderView> createState() => _ReaderViewState();
}

class _ReaderViewState extends ConsumerState<ReaderView>
    with SingleTickerProviderStateMixin {
  late final PageController _pageController;
  late final ScrollController _scrollController;
  late final AnimationController _bounceController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
  );

  late final ReaderPageLoader _loader;

  /// 进度落盘器（串行化 + 最后一次写入优先）。initState 里取好，dispose 也能直接用。
  ProgressRecorder? _recorder;
  AlbumRepository? _repository;
  late ReaderMode _mode;
  late int _page;

  /// 拖动进度条时的「预览页」：只改 HUD 显示，不写 [_page]。
  ///
  /// 之前直接把 `_page` 改掉，松手时 `_goToPage(value)` 发现目标页 == 当前页就直接
  /// return，于是进度条拖完什么都没发生。
  int? _dragPage;
  bool _hudVisible = true;
  bool _locked = false;
  bool _switchingLine = false;
  bool _exporting = false;
  Timer? _hudTimer;

  /// 退出闸门：返回键 / 退出按钮在「落盘 await」窗口内被重复触发时只弹一次栈，
  /// 否则第二次 `_safePop` 会把上一页也一起弹掉。
  bool _exiting = false;

  /// LiquidGlass「更多」的玻璃气泡菜单控制器（Metal 走 AppSheet，不用它）。
  final GlassMenuController _moreMenuController = GlassMenuController();

  /// 更多菜单是否「开着」（不含正在收起）。
  ///
  /// `GlassPullDownButton` 没有 onOpen 回调，只能靠两个真实信号拼出来：
  /// - 打开：菜单的 barrier 会吃掉打开后的所有点击，所以触发器上的 pointer-down
  ///   只可能是「开菜单」（见 [_glassMoreButton] 的 Listener）；
  /// - 关闭：`onClose` 在收起动画**开始**时就同步触发。
  ///
  /// 不能只看 `controller.isOpen`：它在约 550ms 的收起动画结束前一直是 true，
  /// 而包内 `close()` 在 isClosing 时直接 return，会把收起期间的返回键吃掉。
  bool _moreMenuOpen = false;

  DateTime _lastProgressWrite = DateTime.fromMillisecondsSinceEpoch(0);
  double _bounceOffset = 0;

  /// 每页一个缩放控制器（由本 State 持有并释放）：双击缩放要能跨「三分区」触发。
  final Map<int, TransformationController> _pageZoom =
      <int, TransformationController>{};

  /// 竖读整屏缩放（条漫模式）：缩放整块阅读区，而不是单张图。
  static const double _verticalMaxScale = 4;
  double _verticalScale = 1;
  Offset _verticalOffset = Offset.zero;
  final Map<int, Offset> _verticalPointers = <int, Offset>{};
  double _pinchBaseScale = 1;
  double _pinchBaseDistance = 0;
  Offset _pinchBaseOffset = Offset.zero;
  Offset _pinchBaseFocal = Offset.zero;

  int get _total => widget.total;
  bool get _isOnline => widget.onlineData != null;
  ReaderData get _onlineData => widget.onlineData!;

  /// 正文页数 + 末尾的结束页。
  ///
  /// `_page` 只在这 `1.._pageCount` 之间取值，但**进度、HUD、预取永远按 [_total] 算**，
  /// 结束页不会被记成「第 total+1 页」，也不会拿越界页号去取图。
  int get _pageCount => _isOnline ? _total + 1 : _total;

  /// 当前停在结束页（左右翻页模式）。
  bool get _atEndPage => _page > _total;

  /// 竖读时结束页的固定高度（占屏高比例）。
  ///
  /// 固定高度让「正文可滚动高度 = maxScrollExtent - 结束页高度」是确定值，
  /// 页码比例与 `_goToPage` / 模式切换都只按正文高度算，结束页不参与页比率。
  static const double _endPageExtentRatio = 0.72;

  double get _endPageExtent =>
      _isOnline ? MediaQuery.sizeOf(context).height * _endPageExtentRatio : 0;

  /// 竖读正文可滚动高度（不含末尾结束页）。
  double get _verticalContentExtent {
    if (!_scrollController.hasClients) return 0;
    final extent = _scrollController.position.maxScrollExtent - _endPageExtent;
    return extent > 0 ? extent : 0;
  }

  @override
  void initState() {
    super.initState();
    _mode = widget.mode;
    _page = clampReaderPage(widget.initialPage, _total);
    if (_isOnline) _recorder = ref.read(readerProgressRecorderProvider);
    _pageController = PageController(initialPage: _page - 1);
    _scrollController = ScrollController();
    _loader = ReaderPageLoader(
      total: _total,
      fetch: _fetchPage,
      onChanged: () {
        if (mounted) setState(() {});
      },
    );
    _bounceController.addListener(() {
      final value = math.sin(_bounceController.value * math.pi) * 8;
      setState(() => _bounceOffset = value);
    });
    // HUD 一进来就是可见的，所以系统状态栏也要可见（edgeToEdge）：
    // 顶部底板正好铺在状态栏后面，OS 图标由系统画在底板之上。
    // 只有沉浸阅读（HUD 自动/手动隐藏）时才切 immersiveSticky —— 否则会出现
    // 「HUD 可见 + 系统栏隐藏」的 28px 纯色幻影额头。
    unawaited(_applySystemUi(false));
    // 进入阅读器就排队：当前页 + 后续 5 页 + 回看 2 页，槽位空出来自动补位。
    _loader.setFocus(_page);
    if (_mode == ReaderMode.vertical && _page > 1) {
      final ratio = (_page - 1) / (_total - 1);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _mode == ReaderMode.vertical) {
          _scrollToVerticalRatio(ratio);
        }
      });
    }
    _restartHudTimer();
  }

  @override
  void dispose() {
    _hudTimer?.cancel();
    _loader.dispose();
    _bounceController.dispose();
    _pageController.dispose();
    _scrollController.dispose();
    for (final controller in _pageZoom.values) {
      controller.dispose();
    }
    _pageZoom.clear();
    // 任何退出路径（HUD 退出 / 系统返回 / 菜单关闭 / 路由被替换）都在这里兜一次：
    // 同步取快照入队，再尽力 flush 落盘，不依赖 widget 树还活着。
    unawaited(_persistProgress());
    unawaited(_recorder?.flush());
    unawaited(_applySystemUi(false));
    super.dispose();
  }

  /// 取该页的缩放控制器（第一次用到时创建，随 State 一起释放）。
  TransformationController _zoomControllerOf(int page) =>
      _pageZoom.putIfAbsent(page, TransformationController.new);

  Future<void> _applySystemUi(bool immersive) async {
    try {
      await SystemChrome.setEnabledSystemUIMode(
        immersive ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
      );
    } catch (_) {
      // 桌面 / 测试环境忽略。
    }
  }

  // ---------------------------------------------------------------- 页面加载
  /// 单页加载入口（下载 + 切片还原），由 [ReaderPageLoader] 统一调度并发与重试。
  Future<Uint8List?> _fetchPage(int page) async {
    final loadPage = widget.loadPage;
    if (loadPage != null) return loadPage(page);
    final data = _onlineData;
    final repository = await _repositoryInstance();
    return repository.loadPage(
      photoId: data.args.chapterId,
      filename: data.chapter.images[page - 1],
      scrambleIdOverride: data.scrambleId,
    );
  }

  Future<AlbumRepository> _repositoryInstance() async {
    final cached = _repository;
    if (cached != null) return cached;
    final repository = await ref.read(albumRepositoryProvider.future);
    _repository = repository;
    return repository;
  }

  // ---------------------------------------------------------------- 翻页
  /// [animate] 为 null 时按设置里的「翻页动画」开关决定：关掉就是瞬切。
  void _goToPage(int page, {bool? animate, bool bounceAtEdge = true}) {
    final target = page.clamp(1, _pageCount).toInt();
    if (target == _page) {
      if (bounceAtEdge && (target <= 1 || target >= _pageCount)) {
        _bounceController.forward(from: 0);
        HapticFeedback.lightImpact();
      }
      return;
    }
    setState(() {
      _page = target;
      _dragPage = null;
    });
    // 结束页没有正文图片：预取焦点永远夹在正文页内。
    _loader.setFocus(math.min(target, _total));
    unawaited(_persistProgress(throttle: true));
    _restartHudTimer();

    final smooth = animate ?? ref.read(settingsProvider).pageTurnAnimation;
    if (_mode == ReaderMode.paged) {
      if (smooth) {
        _pageController.animateToPage(
          target - 1,
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
        );
      } else {
        _pageController.jumpToPage(target - 1);
      }
    } else if (_scrollController.hasClients) {
      // 竖读：按「正文可滚动高度」定位，末尾结束页不参与页比率。
      final contentPage = math.min(target, _total);
      final ratio = _total <= 1 ? 0.0 : (contentPage - 1) / (_total - 1);
      _scrollToVerticalRatio(ratio);
    }
  }

  /// 竖读按比例定位（跳页 / 进度条拖动 / 切模式共用）。
  ///
  /// ListView 是懒加载的：第一次 jump 时末尾结束页可能还没参与布局，
  /// `maxScrollExtent` 只是估算值。布局稳定后按真实正文高度校正一次，
  /// 保证「第 N 页」落在正文页上，而不是被结束页的高度带偏。
  void _scrollToVerticalRatio(double ratio) {
    if (!_scrollController.hasClients) return;
    _scrollController.jumpTo(ratio * _verticalContentExtent);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final corrected = ratio * _verticalContentExtent;
      if ((corrected - _scrollController.position.pixels).abs() > 1) {
        _scrollController.jumpTo(corrected);
      }
    });
  }

  void _commitHudSeek(int page) {
    final glass = context.isLiquidGlass;
    if (_dragPage != null) setState(() => _dragPage = null);
    _goToPage(page, animate: glass ? false : null, bounceAtEdge: !glass);
  }

  void _previousPage() {
    if (_page <= 1) {
      _bounceController.forward(from: 0);
      HapticFeedback.lightImpact();
      return;
    }
    _goToPage(_page - 1);
  }

  void _nextPage() {
    if (_page >= _pageCount) {
      _bounceController.forward(from: 0);
      HapticFeedback.lightImpact();
      return;
    }
    _goToPage(_page + 1);
  }

  /// 竖读「翻一屏」：按视口高度整屏移动，到边界回弹。
  ///
  /// [direction] 为 `1` 向后（往下）翻一屏，`-1` 向前（往上）翻一屏。
  ///
  /// 竖读本来就是无动画的（跳页 / 切模式都用 `jumpTo`）：这里同样瞬切，
  /// 连点也不会被上一段动画吞掉半屏，`_page` 由滚动通知照常回写进度。
  void _turnVerticalScreen(int direction) {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    final screen = position.viewportDimension;
    if (screen <= 0) return;
    _restartHudTimer();
    final target = (position.pixels + direction * screen)
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    if ((target - position.pixels).abs() < .5) {
      _bounceController.forward(from: 0);
      HapticFeedback.lightImpact();
      return;
    }
    _scrollController.jumpTo(target);
  }

  /// 竖读单击三分区：左翻上一屏，中显示详情（HUD），右翻下一屏。
  ///
  /// 和左右翻页共用同一套比例（[readerTapZoneAt]）：换模式不换手感。
  void _onVerticalTapUp(TapUpDetails details) {
    final width = MediaQuery.sizeOf(context).width;
    switch (readerTapZoneAt(details.localPosition.dx, width)) {
      case ReaderTapZone.previous:
        _turnVerticalScreen(-1);
      case ReaderTapZone.hud:
        _toggleHud();
      case ReaderTapZone.next:
        _turnVerticalScreen(1);
    }
  }

  /// 落盘当前进度。
  ///
  /// 不再走 `_repository`（仓储还没初始化的退出路径会把进度直接丢掉）：
  /// 直接交给 [ProgressRecorder]，由它串行化 + 最后一次写入优先地写进 ProgressStore。
  Future<void> _persistProgress({bool throttle = false}) async {
    if (_total <= 0) return;
    if (throttle &&
        DateTime.now().difference(_lastProgressWrite) <
            AppConfig.progressWriteThrottle) {
      return;
    }
    _lastProgressWrite = DateTime.now();
    final page = clampReaderPage(_page, _total);
    final data = widget.onlineData;
    if (data == null) {
      await widget.onProgress?.call(page);
      return;
    }
    await _recorder!.record(
      ProgressSnapshot(
        albumId: data.args.albumId,
        chapterId: data.args.chapterId,
        page: page,
        total: _total,
        albumTitle: data.args.albumTitle,
        chapterTitle: data.title,
      ),
    );
  }

  // ---------------------------------------------------------------- HUD
  void _toggleHud() {
    setState(() => _hudVisible = !_hudVisible);
    unawaited(_applySystemUi(!_hudVisible));
    if (_hudVisible) {
      _restartHudTimer();
    } else {
      _hudTimer?.cancel();
    }
  }

  void _restartHudTimer() {
    _hudTimer?.cancel();
    if (!_hudVisible) return;
    _hudTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      // 玻璃「更多」菜单开着时不能隐藏 HUD：弹出菜单的 trigger 就在 HUD 里，
      // 一隐藏就会把 GlassMenu 连同它的 OverlayPortal 一起卸载。
      if (_moreMenuController.isOpen) {
        _restartHudTimer();
        return;
      }
      setState(() => _hudVisible = false);
      unawaited(_applySystemUi(true));
    });
  }

  /// 「更多」菜单开始收起（点选 / 点空白 / 再点 trigger / 路由变化）：
  /// 清掉「开着」标记，并恢复 HUD 自动隐藏的 3 秒计时。
  ///
  /// 收尾魔像还在跑时 `controller.isOpen` 仍为 true，但这里已经允许返回键退出。
  void _onMoreMenuClosed() {
    _moreMenuOpen = false;
    if (!mounted || !_hudVisible) return;
    _restartHudTimer();
  }

  void _toggleMode() {
    final next = _mode.toggled;
    final contentPage = math.min(_page, _total);
    final ratio = _total <= 1 ? 0.0 : (contentPage - 1) / (_total - 1);
    setState(() {
      _mode = next;
      _hudVisible = true;
      // 换模式时把竖读整屏缩放归位，避免残留的放大/平移带到另一种模式。
      _verticalScale = 1;
      _verticalOffset = Offset.zero;
    });
    unawaited(
      ref.read(settingsProvider.notifier).setDefaultReaderMode(next.code),
    );
    _restartHudTimer();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (next == ReaderMode.paged) {
        if (_pageController.hasClients) _pageController.jumpToPage(_page - 1);
      } else if (_scrollController.hasClients) {
        // 竖读同样只按正文高度定位（结束页不计入页比率）。
        _scrollToVerticalRatio(ratio);
      }
    });
  }

  /// HUD 退出 / 系统返回：先把当前页落盘（尽量 await），再弹栈。
  ///
  /// [_exiting] 是重入闸门：落盘 await 窗口里再按返回 / 再点退出按钮只会走一次
  /// `_safePop`，不会连退两层。落盘失败也不会卡死退出（finally 语义由
  /// [_recorder] 内部的队列保证，这里只关心弹栈）。
  Future<void> _exit() async {
    if (_exiting) return;
    _exiting = true;
    await _persistProgress();
    await _recorder?.flush();
    if (!mounted) return;
    widget.onExit();
  }

  /// 系统 / 外部发起的真实弹栈（`didPop == true`）：先同步取快照入队，再尽力 flush。
  ///
  /// 和 [_exit] 相比这里不弹栈（弹栈已经发生），重复落盘由 [ProgressRecorder]
  /// 串行化 + 最后一次写入优先消解，和改动前语义一致。
  void _handleSystemPop(bool didPop) {
    unawaited(_persistProgress());
    if (didPop) unawaited(_recorder?.flush());
  }

  // ---------------------------------------------------------------- 更多菜单
  /// 二级菜单：翻页方式 / 翻页动画开关 / 选择节点（三级菜单）/ 下载当页图片。
  Future<void> _openMoreMenu() async {
    _hudTimer?.cancel();
    final action = await AppSheet.show<String>(
      context: context,
      showDragHandle: true,
      backgroundColor: AppColors.darkSurfaceContainer,
      builder: (sheetContext) => ReaderControlsTheme(
        child: SafeArea(child: _moreMenu(sheetContext)),
      ),
    );
    if (!mounted) return;
    _restartHudTimer();
    switch (action) {
      case 'mode':
        _toggleMode();
      case 'line':
        await _pickLine();
      case 'save':
        await _saveCurrentPage();
    }
  }

  Widget _moreMenu(BuildContext sheetContext) {
    const ink = AppColors.readerInk;
    TextStyle titleStyle() => AppTypography.body.copyWith(color: ink);
    TextStyle subStyle() =>
        AppTypography.micro.copyWith(color: ink.withValues(alpha: .7));
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '更多',
              style: AppTypography.sectionTitle.copyWith(color: ink),
            ),
          ),
        ),
        // 每行「图标 · 标题 · 右侧取值」压在同一根中线上，副标题另起一行：
        // 之前用 ListTile 的 title + subtitle + trailing，Material 把 trailing
        // 垂直居中到两行之间，肉眼就是「文字和按钮没对齐」。
        _MoreMenuRow(
          icon: SvgIcon(_mode.icon, size: 20),
          title: '翻页方式',
          value: _mode.label,
          subtitle: '点击切换到${_mode.toggled.label}',
          titleStyle: titleStyle(),
          subtitleStyle: subStyle(),
          onTap: () => Navigator.of(sheetContext).pop('mode'),
        ),
        // 翻页动画开关：和「我的 - 翻页动画」同一个设置项，改了立刻生效
        //（[_goToPage] 里 `animate == null` 时就按它决定瞬切还是滑动）。
        _MoreMenuRow(
          icon: const SvgIcon(AppIcons.pageMode, size: 20),
          title: '翻页动画',
          subtitle: '关闭后翻页瞬切，不做滑动过渡',
          titleStyle: titleStyle(),
          subtitleStyle: subStyle(),
          trailing: const _PageTurnSwitch(),
          onTap: _togglePageTurnAnimation,
        ),
        if (_isOnline)
          _MoreMenuRow(
            icon: const SvgIcon(AppIcons.refresh, size: 20),
            title: '选择节点',
            value: _lineLabel,
            subtitle: '点击换一条分流线路',
            titleStyle: titleStyle(),
            subtitleStyle: subStyle(),
            onTap: () => Navigator.of(sheetContext).pop('line'),
          ),
        _MoreMenuRow(
          icon: const SvgIcon(AppIcons.download, size: 20),
          title: '下载当页图片',
          subtitle: _mode == ReaderMode.paged
              ? '保存为 ${_imageName(math.min(_page, _total))}'
              : '仅左右翻页模式可用',
          titleStyle: titleStyle(),
          subtitleStyle: subStyle(),
          onTap: () => Navigator.of(sheetContext).pop('save'),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  /// 切换「翻页动画」（两套皮肤的更多菜单共用）。
  ///
  /// 立即落盘到 `settingsStore`，`_goToPage` 下一次翻页就按新值走；菜单不用关。
  void _togglePageTurnAnimation() {
    final enabled = ref.read(settingsProvider).pageTurnAnimation;
    unawaited(
      ref.read(settingsProvider.notifier).setPageTurnAnimation(!enabled),
    );
    _restartHudTimer();
  }

  // ---------------------------------------------------------------- 玻璃更多菜单
  /// LiquidGlass「更多」：GlassPullDownButton 从按钮本身灵 morph 出二级玻璃气泡，
  /// 「选择节点」用 GlassMenuItem.submenu 原生展开三级气泡（不再开第二个菜单 / Sheet）。
  ///
  /// 每行只放一行文本：包内 `GlassMenuItem` 的行内容是 Row(图标, 标题+副标题, trailing)、
  /// 且整体垂直居中，带副标题时图标 / 箭头会落在两行中间，就是「文字和按钮没对齐」。
  /// 当前值直接并进标题（或作为 trailing），所有行都只有一行，图标、文字、箭头天然对齐。
  ///
  /// 气泡由根 Overlay 绘制（HUD 只提供触发点），App 主题可能是浅色：
  /// 玻璃设置走 `AppGlassTheme.of(context, reader: true)`，文字 / 图标颜色
  /// 全部显式写成阅读器墨色，任何主题下都是可读的深色阅读器菜单。
  Widget _glassMoreButton(BuildContext context) {
    const ink = AppColors.readerInk;
    final tokens = AppGlassTheme.of(context, reader: true);
    final accessibility = GlassAccessibilityData.of(context);
    final titleStyle = AppTypography.body.copyWith(color: ink);
    final subStyle =
        AppTypography.micro.copyWith(color: ink.withValues(alpha: .66));
    Widget iconOf(String asset) => SvgIcon(asset, size: 18, color: ink);
    return Listener(
      // 唯一可靠的「开菜单」信号：菜单的 barrier 会吃掉打开后的所有点击，
      // 所以触发器上的 pointer-down 只可能是在开菜单。仅置标记，不 setState
      // （重建会让菜单在打开动画里换 items）。
      onPointerDown: (_) => _moreMenuOpen = true,
      child: GlassPullDownButton(
        icon: const SvgIcon(AppIcons.more, size: 16, color: ink),
        semanticLabel: '更多',
        menuSemanticLabel: '更多操作',
        buttonWidth: 34,
        buttonHeight: 34,
        menuWidth: 264,
        // 面板与二级卡片都按超椭圆（连续曲率）绘制，这里给 iOS 26 的 28。
        menuBorderRadius: 28,
        controller: _moreMenuController,
        settings: tokens.overlay,
        quality: AppGlassTheme.overlayQuality,
        morphSpeed:
            accessibility.reduceMotion ? MorphSpeed.instant : MorphSpeed.normal,
        onClose: _onMoreMenuClosed,
        items: <Widget>[
          GlassMenuItem(
            title: '翻页方式',
            icon: iconOf(_mode.icon),
            titleStyle: titleStyle,
            iconColor: ink,
            // 单行：标题与右侧取值同一条中线，不再把 trailing 挂在两行文字中间。
            trailing: Text('切换到${_mode.toggled.label}', style: subStyle),
            enablePressScale: !accessibility.reduceMotion,
            onTap: _toggleMode,
          ),
          // 翻页动画开关：与「我的 - 翻页动画」同一设置项。开关行不是 GlassMenuItem
          //（见 [_PageTurnGlassRow]），点开关只切设置，气泡不会顺带收起。
          _PageTurnGlassRow(
            icon: iconOf(AppIcons.pageMode),
            titleStyle: titleStyle,
            onTap: _togglePageTurnAnimation,
          ),
          if (_isOnline)
            GlassMenuItem(
              title: '选择节点',
              icon: iconOf(AppIcons.refresh),
              titleStyle: titleStyle,
              iconColor: ink,
              enablePressScale: !accessibility.reduceMotion,
              // 带 submenu 的父行 onTap 必需但不会被调用：激活它是展开三级气泡。
              onTap: () {},
              submenu: _glassLineItems(
                titleStyle: titleStyle,
                subStyle: subStyle,
                ink: ink,
              ),
            ),
          GlassMenuItem(
            title: '下载当页图片',
            icon: iconOf(AppIcons.download),
            titleStyle: titleStyle,
            iconColor: ink,
            enablePressScale: !accessibility.reduceMotion,
            onTap: () => unawaited(_saveCurrentPage()),
          ),
        ],
      ),
    );
  }

  /// 三级气泡：分流列表（当前线路打勾，切线路中整列禁用）。
  ///
  /// 保持单行：主机串放在 trailing（当前线路换成勾），标题与取值同一中线。
  List<Widget> _glassLineItems({
    required TextStyle titleStyle,
    required TextStyle subStyle,
    required Color ink,
  }) {
    final current = ref.read(jmApiProvider).apiHost;
    return <Widget>[
      for (final host in _lineChoices())
        GlassMenuItem(
          key: ValueKey<String>('glass-node-$host'),
          title: JmConstants.lineLabelOf(host),
          titleStyle: titleStyle,
          iconColor: ink,
          trailing: host == current
              ? SvgIcon(AppIcons.check, size: 14, color: ink)
              // 主机串定宽右对齐：大字号/窄面板下只截断它，不把整行挤溢出。
              : SizedBox(
                  width: 104,
                  child: Text(
                    host,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                    style: subStyle,
                  ),
                ),
          semanticsSelected: host == current,
          enabled: !_switchingLine,
          onTap: () => unawaited(_applyLine(host)),
        ),
    ];
  }

  String _imageName(int page) {
    final data = widget.onlineData;
    if (data == null) {
      final title = widget.title.replaceFirst(
        RegExp(r'\.pdf$', caseSensitive: false),
        '',
      );
      return '${safeSegment(title)}-第$page页.png';
    }
    return readerImageName(
      albumId: data.args.albumId,
      chapterTitle: widget.title,
      page: page,
    );
  }

  /// 下载当前页图片：只在左右翻页模式可用。
  Future<void> _saveCurrentPage() async {
    if (_mode != ReaderMode.paged) {
      AppToast.show(
        context,
        '「下载当页图片」只在左右翻页模式可用',
        duration: const Duration(seconds: 3),
      );
      return;
    }
    if (_atEndPage) {
      AppToast.show(
        context,
        '结束页没有图片可保存',
        duration: const Duration(seconds: 3),
      );
      return;
    }
    final page = _page;
    var bytes = _loader.bytesOf(page);
    if (bytes == null) {
      AppToast.show(
        context,
        '正在取第 $page 页，稍等…',
        duration: const Duration(seconds: 2),
      );
      bytes = await _fetchPage(page);
    }
    if (!mounted) return;
    if (bytes == null) {
      AppToast.show(
        context,
        '第 $page 页还没加载完，稍后再试',
        duration: const Duration(seconds: 3),
      );
      return;
    }
    try {
      final saved = await ref
          .read(readerImageSaverProvider)
          .save(_imageName(page), bytes);
      if (!mounted) return;
      AppToast.show(
        context,
        '已保存：${saved.displayPath}',
        duration: const Duration(seconds: 4),
      );
    } catch (error) {
      if (!mounted) return;
      final message = error is PlatformException ? error.message : null;
      AppToast.show(
        context,
        '保存失败：${message ?? error}',
        duration: const Duration(seconds: 4),
      );
    }
  }

  // ---------------------------------------------------------------- 结束页
  /// 结束页：读完当前可阅读单元后挂在正文末尾（不计入 [_total]）。
  ///
  /// [extent] 非空时（竖读）用它给结束页一个固定高度，保证页码比例可扣掉它。
  Widget _endPageView({double? extent}) => ReaderEndPage(
        albumId: _onlineData.args.albumId,
        chapterId: _onlineData.args.chapterId,
        // 存原始专辑标题：为空时文件名只写 JM 号，不回落成章节名。
        albumTitle: _onlineData.args.albumTitle,
        chapterTitle: widget.title,
        total: _total,
        cachedPages: math.min(_loader.cachedCount, _total),
        busyDownload: _exporting,
        embeddedExtent: extent,
        onDownload: _exportToDownloadQueue,
        onTap: _toggleHud,
      );

  /// 结束页「下载」：把「阅读缓存 + 缺页补齐」交给既有下载体系。
  ///
  /// 一次点击只给一条与真实结果一致的 Toast（加入成功 / 已在队列 / 失败），
  /// 不在结果未知时先报成功；按钮在等待期间进入 loading 态作为即时反馈。
  Future<void> _exportToDownloadQueue() async {
    if (_exporting) return;
    final data = _onlineData;
    final albumId = data.args.albumId;
    final chapterId = data.args.chapterId;
    final total = _total;
    if (!canDownloadReaderUnit(
      albumId: albumId,
      chapterId: chapterId,
      total: total,
    )) {
      AppToast.show(
        context,
        '这本没有可导出的页面',
        duration: const Duration(seconds: 3),
      );
      return;
    }

    void openDownloads() {
      if (mounted) context.push('/download');
    }

    setState(() => _exporting = true);
    try {
      final loader = _loader;
      // 快照只用于本任务：每取走一页就从快照里删掉，闭包不长期持有整章字节。
      final snapshot = loader.snapshot();
      final images = data.chapter.images;
      final scramble = data.scrambleId;
      final cachedPages = snapshot.entries
          .where(
            (entry) =>
                entry.key >= 1 && entry.key <= total && entry.value.isNotEmpty,
          )
          .length;
      final job = ReaderExportJob(
        albumId: albumId,
        chapterId: chapterId,
        albumTitle: data.args.albumTitle,
        chapterTitle: widget.title,
        total: total,
        cachedPages: cachedPages,
        fetchPage: (page) async {
          // 缓存优先（快照用完即弃 + loader 现况），缺页才走同一条加载管线。
          final hit = snapshot.remove(page) ?? loader.bytesOf(page);
          if (hit != null && hit.isNotEmpty) return hit;
          if (page < 1 || page > images.length) return null;
          final repository = await _repositoryInstance();
          return repository.loadPage(
            photoId: chapterId,
            filename: images[page - 1],
            scrambleIdOverride: scramble,
          );
        },
      );
      final ticket =
          await ref.read(downloadRepositoryProvider).enqueueReaderExport(job);
      if (!mounted) return;
      AppToast.show(
        context,
        ticket.reused ? '这本已在下载队列中' : '已加入下载队列：${ticket.record.displayTitle}',
        actionLabel: '查看',
        onAction: openDownloads,
      );
    } catch (error) {
      if (mounted) AppToast.show(context, '加入下载队列失败：$error');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  // ---------------------------------------------------------------- 分流
  String get _lineLabel =>
      JmConstants.lineLabelOf(ref.read(jmApiProvider).apiHost);

  /// 当前线路置顶，其余已收录分流按顺序排列，最后是其它/手填线路。
  List<String> _lineChoices() {
    final api = ref.read(jmApiProvider);
    final available = api.availableHosts;
    final current = api.apiHost;
    return <String>[...available]..sort((a, b) {
        if (a == current) return -1;
        if (b == current) return 1;
        final rank =
            JmConstants.lineRankOf(a).compareTo(JmConstants.lineRankOf(b));
        return rank != 0
            ? rank
            : available.indexOf(a).compareTo(available.indexOf(b));
      });
  }

  Future<void> _pickLine() async {
    final hosts = _lineChoices();
    if (hosts.isEmpty) return;
    _hudTimer?.cancel();
    final selected = await AppSheet.show<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.darkSurfaceContainer,
      showDragHandle: true,
      builder: (sheetContext) => ReaderControlsTheme(
        child: SafeArea(
          child: _linePicker(
            sheetContext,
            hosts: hosts,
            onSelect: Navigator.of(sheetContext).pop<String>,
          ),
        ),
      ),
    );
    if (!mounted) return;
    _restartHudTimer();
    if (selected != null) await _applyLine(selected);
  }

  Widget _linePicker(
    BuildContext context, {
    required List<String> hosts,
    required ValueChanged<String> onSelect,
  }) {
    final store = ref.read(endpointStoreProvider);
    final current = ref.read(jmApiProvider).apiHost;
    final glass = context.isLiquidGlass;
    return ConstrainedBox(
      constraints:
          BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .62),
      child: ListView(
        shrinkWrap: true,
        primary: false,
        padding: EdgeInsets.fromLTRB(0, glass ? 14 : 0, 0, 8),
        children: <Widget>[
          Padding(
            padding: EdgeInsets.fromLTRB(glass ? 16 : 20, 0, 20, 6),
            child: Text(
              '切换分流',
              style: AppTypography.sectionTitle
                  .copyWith(color: AppColors.readerInk),
            ),
          ),
          if (!glass)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                'JMComic 常用 4 条分流（线路1-4）；切换后重新拉 /setting 取该线路图床，并按当前页重载',
                style: AppTypography.micro.copyWith(
                  color: AppColors.readerInk.withValues(alpha: .65),
                ),
              ),
            ),
          for (final host in hosts)
            _LineTile(
              host: host,
              current: host == current,
              health: store.healthOf(host),
              onTap: () => onSelect(host),
            ),
        ],
      ),
    );
  }

  Future<void> _applyLine(String selected) async {
    final api = ref.read(jmApiProvider);
    if (!mounted || _switchingLine || selected == api.apiHost) return;
    setState(() => _switchingLine = true);
    final ok = await api.switchApiHost(selected);
    if (!mounted) return;
    setState(() => _switchingLine = false);
    if (!ok) {
      AppToast.show(
        context,
        '${JmConstants.lineLabelOf(selected)} 不可用，已保留原线路',
        duration: const Duration(seconds: 4),
      );
      return;
    }
    // 换线后旧线路的图片作废：清缓存 + 按当前页重新预取。
    _loader.clear();
    _loader.setFocus(_page);
    AppToast.show(
      context,
      '已切到 ${JmConstants.lineLabelOf(selected)}',
      duration: const Duration(seconds: 4),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_total == 0) {
      return const Center(
        child: Text('没有可阅读的页面', style: TextStyle(color: AppColors.readerInk)),
      );
    }

    return PopScope(
      // 返回键统一由阅读器决定：玻璃「更多」菜单开着先收菜单，否则落盘后再弹栈。
      // `canPop: false` 让每次返回都进 [_onPopInvokedWithResult]，由那里按菜单/
      // 退出闸门的真实状态决定去向（app 的 pageTransitions 是 FadeForwards，
      // 没有交互式侧滑返回路径，因此不会丢手势）。
      canPop: false,
      // 真实弹栈（`didPop == true`，例如路由被外部替换）时同步取快照入队并 flush；
      // 不依赖 HUD 退出按钮（dispose 还会再兜一次）。
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          _handleSystemPop(true);
          return;
        }
        // 气泡菜单还开着：第一次返回只收菜单。收起动画期间的第二次返回直接走退出
        // （`_moreMenuOpen` 在 onClose 时就已清掉，不再被 controller.isOpen 卡住）。
        if (_moreMenuOpen) {
          _moreMenuOpen = false;
          if (_moreMenuController.isOpen) {
            _moreMenuController.close();
            return;
          }
        }
        // 先落盘再弹栈（和 HUD 退出按钮同一条路径，带重入闸门）。
        unawaited(_exit());
      },
      child: Stack(
        children: <Widget>[
          Positioned.fill(
            child: Transform.translate(
              offset: Offset(_bounceOffset, 0),
              child: _buildReaderBody(),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            bottom: 0,
            child: ReaderHud(
              title: widget.title,
              // 拖动进度条时显示预览页，松手才真正翻页。
              page: math.min(_dragPage ?? _page, _total),
              total: _total,
              mode: _mode,
              visible: _hudVisible,
              // 翻页方式 / 选择节点 / 下载当页图片都收进这个「更多」按钮。
              // 玻璃皮肤用 GlassPullDownButton（三级 submenu），Metal 仍是 AppSheet。
              onMore: context.isLiquidGlass
                  ? null
                  : () => unawaited(_openMoreMenu()),
              glassMoreBuilder: context.isLiquidGlass ? _glassMoreButton : null,
              onExit: () => unawaited(_exit()),
              onToggleMode: _toggleMode,
              onJump: _commitHudSeek,
              onSliderCancel: () {
                if (_dragPage != null) setState(() => _dragPage = null);
              },
              onSliderChanged: (value) {
                setState(() {
                  _dragPage = clampReaderPage(value.round(), _total);
                });
                _restartHudTimer();
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReaderBody() {
    if (_mode == ReaderMode.paged) {
      return ReaderTapZones(
        // 缩放中只关单击（防止误翻页）；结束页上的按钮需要拿到点击，也关掉三分区。
        enabled: !_locked && !_atEndPage,
        onDoubleTap: _atEndPage ? null : _toggleZoomCurrent,
        onPrevious: _previousPage,
        onNext: _nextPage,
        onToggleHud: _toggleHud,
        child: PageTurnView(
          controller: _pageController,
          total: _pageCount,
          // 缩放中把横向拖动让给图片平移，否则会一边放大一边翻页。
          physics: _locked ? const NeverScrollableScrollPhysics() : null,
          onPageChanged: (page) {
            if (page == _page) return;
            setState(() {
              _page = page;
              _dragPage = null;
            });
            _loader.setFocus(math.min(page, _total));
            unawaited(_persistProgress(throttle: true));
          },
          itemBuilder: _pagedItem,
        ),
      );
    }

    return Listener(
      onPointerDown: _onVerticalPointerDown,
      onPointerMove: _onVerticalPointerMove,
      onPointerUp: _onVerticalPointerEnd,
      onPointerCancel: _onVerticalPointerEnd,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        // 三分区落点：左翻上一屏，中显示详情（HUD），右翻下一屏。
        // 用外层 onTapUp 而不是叠一层点击区：结束页上的按钮必须还能拿到点击。
        onTapUp: _onVerticalTapUp,
        onDoubleTap: _toggleVerticalZoom,
        // 放大后横向拖动用来左右看边缘；纵向仍交给列表滚动。
        onHorizontalDragUpdate: _verticalZoomed ? _panVerticalZoom : null,
        child: Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..translate(_verticalOffset.dx, _verticalOffset.dy)
            ..scale(_verticalScale),
          child: ScrollReaderView(
            controller: _scrollController,
            total: _total,
            // 末尾多挂一个结束页；页码估算只按正文页（扣掉结束页高度）。
            itemCount: _pageCount,
            footerExtent: _endPageExtent,
            itemExtent: _isOnline ? null : MediaQuery.sizeOf(context).height,
            // 双指按下 / 放大中锁住纵向滚动；单指仍是正常滚动。
            physics: _locked ? const NeverScrollableScrollPhysics() : null,
            onPageChanged: (page) {
              if (page == _page) return;
              setState(() {
                _page = page;
                _dragPage = null;
              });
              _loader.setFocus(page);
              unawaited(_persistProgress(throttle: true));
            },
            // 条漫模式不再逐页缩放：双指放大的是整屏漫画。
            itemBuilder: (context, index) =>
                _pageContent(index + 1, endExtent: _endPageExtent),
          ),
        ),
      ),
    );
  }

  /// 左右翻页的单页：正文页可缩放，结束页不套缩放（按钮手势优先）。
  Widget _pagedItem(BuildContext context, int index) {
    final page = index + 1;
    if (page > _total) return _endPageView();
    return _ZoomablePage(
      controller: _zoomControllerOf(page),
      onInteractionChanged: _setLocked,
      child: _pageContent(page),
    );
  }

  /// 竖读整屏是否处于放大状态。
  bool get _verticalZoomed => _verticalScale > 1.01;

  /// 竖读双击：整屏在 1.0 与 2.2 之间切换（居中放大）。
  void _toggleVerticalZoom() {
    setState(() {
      if (_verticalZoomed) {
        _verticalScale = 1;
      } else {
        _verticalScale = _ZoomablePage.doubleTapScale;
      }
      _verticalOffset = Offset.zero;
    });
    _restartHudTimer();
  }

  void _onVerticalPointerDown(PointerDownEvent event) {
    _verticalPointers[event.pointer] = event.position;
    if (_verticalPointers.length >= 2) {
      final points = _verticalPointers.values.toList(growable: false);
      _pinchBaseDistance = (points.first - points.last).distance;
      _pinchBaseScale = _verticalScale;
      _pinchBaseOffset = _verticalOffset;
      _pinchBaseFocal = (points.first + points.last) / 2;
      _setLocked(true);
    }
  }

  void _onVerticalPointerMove(PointerMoveEvent event) {
    if (!_verticalPointers.containsKey(event.pointer)) return;
    _verticalPointers[event.pointer] = event.position;
    if (_verticalPointers.length < 2 || _pinchBaseDistance <= 0) return;
    final points = _verticalPointers.values.toList(growable: false);
    final distance = (points.first - points.last).distance;
    final scale = (_pinchBaseScale * distance / _pinchBaseDistance)
        .clamp(1.0, _verticalMaxScale)
        .toDouble();
    final size = MediaQuery.sizeOf(context);
    final center = size.center(Offset.zero);
    final focal = (points.first + points.last) / 2;
    // 双指中点下面那一点在缩放前后保持不动（两指一起移动时也跟着平移）。
    final ratio = scale / _pinchBaseScale;
    final raw =
        focal - center - (_pinchBaseFocal - center - _pinchBaseOffset) * ratio;
    final limitX = size.width * (scale - 1) / 2;
    final limitY = size.height * (scale - 1) / 2;
    final offset = Offset(
      raw.dx.clamp(-limitX, limitX),
      raw.dy.clamp(-limitY, limitY),
    );
    if ((scale - _verticalScale).abs() < 0.001 && offset == _verticalOffset) {
      return;
    }
    setState(() {
      _verticalScale = scale <= 1.01 ? 1 : scale;
      _verticalOffset = _verticalScale == 1 ? Offset.zero : offset;
    });
  }

  void _onVerticalPointerEnd(PointerEvent event) {
    _verticalPointers.remove(event.pointer);
    if (_verticalPointers.length < 2) {
      _pinchBaseDistance = 0;
      _setLocked(false);
    }
  }

  /// 放大后左右平移（纵向靠列表滚动，不在这里做）。
  void _panVerticalZoom(DragUpdateDetails details) {
    final width = MediaQuery.sizeOf(context).width;
    final limit = width * (_verticalScale - 1) / 2;
    setState(() {
      _verticalOffset = Offset(
        (_verticalOffset.dx + details.delta.dx).clamp(-limit, limit),
        _verticalOffset.dy,
      );
    });
  }

  /// 单指未缩放时允许翻页；双指按下或已放大就锁住翻页/滚动，把拖动让给图片。
  void _setLocked(bool locked) {
    if (_locked == locked) return;
    setState(() => _locked = locked);
    if (!locked) _restartHudTimer();
  }

  /// 双击当前页：1.0 与 2.2 之间切换（居中放大）。
  void _toggleZoomCurrent() {
    final controller = _zoomControllerOf(_page);
    if (controller.value.getMaxScaleOnAxis() > 1.01) {
      controller.value = Matrix4.identity();
      return;
    }
    controller.value = Matrix4.identity()..scale(_ZoomablePage.doubleTapScale);
  }

  Widget _pageContent(int page, {double? endExtent}) =>
      _pageImage(page, endExtent: endExtent);

  Widget _pageImage(int page, {double? endExtent}) {
    if (page > _total) return _endPageView(extent: endExtent);
    final bytes = _loader.bytesOf(page);
    if (bytes != null) {
      return Center(
        child: Image.memory(
          bytes,
          fit: BoxFit.contain,
          gaplessPlayback: true,
        ),
      );
    }
    if (_loader.isFailed(page)) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const IconTheme(
              data: IconThemeData(color: AppColors.readerInk),
              child: SvgIcon(AppIcons.alert, size: 26),
            ),
            const SizedBox(height: 10),
            Text(
              '第 $page 页加载失败',
              style: AppTypography.caption.copyWith(color: AppColors.readerInk),
            ),
            const SizedBox(height: 10),
            // 单页重试也是药丸形，不再是小圆角方块。
            AppButton.text(
              onPressed: () {
                _loader.request(page);
              },
              cornerRadius: AppColors.radiusPill,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }
    return const Center(
      child: SizedBox(
        width: 24,
        height: 24,
        child: AppProgressIndicator.circular(
          size: 24,
          strokeWidth: 2.4,
          color: AppColors.readerInk,
        ),
      ),
    );
  }
}

/// 单页缩放：双指捏合 1.0–4.0（双击由阅读器统一处理，避免和三分区争手势）。
///
/// 控制器由外层持有：双击缩放要在「三分区」的中间区触发，控制器必须能跨层访问。
/// 锁定状态（放大中 **或** 两根手指按下）通过 [onInteractionChanged] 回传：
/// 后者是 0.3.3 修的「双指拖动」问题——之前只有放大后才锁翻页，双指刚落下时
/// 横向拖动会先把页面翻走，看起来就是「双指拖动乱跑」。
class _ZoomablePage extends StatefulWidget {
  const _ZoomablePage({
    required this.controller,
    required this.child,
    required this.onInteractionChanged,
  });

  static const double doubleTapScale = 2.2;
  static const double maxScale = 4;

  final TransformationController controller;
  final Widget child;
  final ValueChanged<bool> onInteractionChanged;

  @override
  State<_ZoomablePage> createState() => _ZoomablePageState();
}

class _ZoomablePageState extends State<_ZoomablePage> {
  bool _zoomed = false;
  int _pointers = 0;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTransformChanged);
  }

  @override
  void didUpdateWidget(covariant _ZoomablePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onTransformChanged);
      widget.controller.addListener(_onTransformChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTransformChanged);
    super.dispose();
  }

  double get _scale => widget.controller.value.getMaxScaleOnAxis();

  bool get _locked => _zoomed || _pointers >= 2;

  void _report() => widget.onInteractionChanged(_locked);

  void _onTransformChanged() {
    final zoomed = _scale > 1.01;
    if (zoomed == _zoomed) return;
    setState(() => _zoomed = zoomed);
    _report();
  }

  void _onPointerDown(PointerDownEvent event) {
    _pointers++;
    if (_pointers >= 2) _report();
  }

  void _onPointerUp(PointerEvent event) {
    if (_pointers > 0) _pointers--;
    if (_pointers < 2) _report();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _onPointerDown,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerUp,
      child: InteractiveViewer(
        transformationController: widget.controller,
        minScale: 1,
        maxScale: _ZoomablePage.maxScale,
        // 未放大时不吃单指拖动，保证翻页手势优先；双指仍然可以捏合/平移。
        panEnabled: _zoomed,
        scaleEnabled: true,
        onInteractionEnd: (_) {
          // 缩回 1.0 附近就彻底归位，避免留下半个像素的偏移。
          if (_scale <= 1.01) widget.controller.value = Matrix4.identity();
        },
        child: widget.child,
      ),
    );
  }
}

/// 分流列表项：线路标签 + 主机 + 最近一次实测延迟/状态。
class _LineTile extends StatelessWidget {
  const _LineTile({
    required this.host,
    required this.current,
    required this.health,
    required this.onTap,
  });

  final String host;
  final bool current;
  final JmHostHealth? health;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ok = health?.ok;
    final detail = health == null
        ? '未测'
        : (ok == true ? '${health!.latencyMs} ms' : '不可用');
    final currentLabel = Text(
      '当前',
      style:
          AppTypography.micro.copyWith(color: AppColors.darkOnPrimaryContainer),
    );
    return AppListTile(
      onTap: onTap,
      title: Row(
        children: <Widget>[
          Text(
            JmConstants.lineLabelOf(host),
            style: AppTypography.body.copyWith(color: AppColors.readerInk),
          ),
          if (current) ...<Widget>[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: AppColors.darkPrimaryContainer,
                borderRadius: BorderRadius.circular(6),
              ),
              child: currentLabel,
            ),
          ],
        ],
      ),
      subtitle: Text(
        host,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTypography.micro
            .copyWith(color: AppColors.readerInk.withValues(alpha: 0.6)),
      ),
      trailing: Text(
        detail,
        style: AppTypography.micro.copyWith(
          color: ok == true ? AppColors.darkPrimary : AppColors.darkInkVariant,
        ),
      ),
    );
  }
}

/// 「更多」二级菜单的一行：图标、标题、右侧取值压在同一根中线上，副标题另起一行。
///
/// 之前用 `ListTile` 的 title + subtitle + trailing，Material 会把 trailing
/// 垂直居中到两行之间（图标同理），看起来就是「文字和按钮没对齐」。
/// 这里把标题行显式做成一个 Row，图标固定 21（body 字号 14 × 1.5）居中于标题行。
class _MoreMenuRow extends StatelessWidget {
  const _MoreMenuRow({
    required this.icon,
    required this.title,
    required this.titleStyle,
    required this.subtitleStyle,
    required this.onTap,
    this.value,
    this.subtitle,
    this.trailing,
  });

  final Widget icon;
  final String title;
  final String? value;
  final String? subtitle;

  /// 标题行右侧控件（例如开关）；给了它就不再画 [value] 文本。
  final Widget? trailing;
  final TextStyle titleStyle;
  final TextStyle subtitleStyle;
  final VoidCallback onTap;

  /// 与 [titleStyle]（14 × 1.5）等高的标题行，图标和右侧取值都按它居中。
  static const double _titleRowHeight = 21;

  @override
  Widget build(BuildContext context) {
    const ink = AppColors.readerInk;
    // 标题行右侧的取值文本（和标题同一中线）；开关这类高控件走外层 trailing，
    // 按整行垂直居中，不塞进 21 高的标题行里撑破布局。
    final valueText = value == null ? null : Text(value!, style: subtitleStyle);
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        // 连续曲率的触点高亮，和 LiquidGlass 一侧的面板曲率一致。
        customBorder: const RoundedSuperellipseBorder(
          borderRadius: BorderRadius.all(Radius.circular(14)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    // 图标按标题行的中线对齐，而不是两行文字块的中线。
                    SizedBox(
                      width: 20,
                      height: _titleRowHeight,
                      child: Center(
                        child: IconTheme(
                          data: const IconThemeData(color: ink),
                          child: icon,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          SizedBox(
                            height: _titleRowHeight,
                            child: Row(
                              children: <Widget>[
                                Expanded(
                                  child: Text(
                                    title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: titleStyle,
                                  ),
                                ),
                                if (valueText != null) ...<Widget>[
                                  const SizedBox(width: 10),
                                  Flexible(child: valueText),
                                ],
                              ],
                            ),
                          ),
                          if (subtitle != null) ...<Widget>[
                            const SizedBox(height: 1),
                            Text(
                              subtitle!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: subtitleStyle,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (trailing != null) ...<Widget>[
                const SizedBox(width: 10),
                trailing!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 玻璃「更多」菜单里的「翻页动画」开关行。
///
/// 不能塞进 [GlassMenuItem]：包内菜单把菜单体上任何一次点击都当「激活命中的菜单项」，
/// 先切开关再收起气泡，极端情况下开关与整行还会各触发一次（净结果不变）。
/// 非 `GlassMenuItem` 的自定义行不参与激活，所以开关自己吃掉点击、气泡保持打开，
/// 点整行（开关以外的地方）也能切。
class _PageTurnGlassRow extends StatelessWidget implements PreferredSizeWidget {
  const _PageTurnGlassRow({
    required this.icon,
    required this.titleStyle,
    required this.onTap,
  });

  final Widget icon;
  final TextStyle titleStyle;
  final VoidCallback onTap;

  /// 单行布局：标题 21 + 上下各 10 内边距，52 也容得下 1.3 倍字号与 28 高的开关。
  @override
  Size get preferredSize => const Size.fromHeight(52);

  @override
  Widget build(BuildContext context) {
    const ink = AppColors.readerInk;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        customBorder: const RoundedSuperellipseBorder(
          borderRadius: BorderRadius.all(Radius.circular(14)),
        ),
        child: SizedBox(
          height: preferredSize.height,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: <Widget>[
                IconTheme(data: const IconThemeData(color: ink), child: icon),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '翻页动画',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: titleStyle,
                  ),
                ),
                const SizedBox(width: 10),
                const _PageTurnSwitch(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 「更多」菜单里的「翻页动画」开关（两套皮肤共用）。
///
/// 值直接来自 `settingsProvider`（和「我的 - 翻页动画」同一项），改成开关后
/// 阅读器下一次翻页立刻按新值走；颜色用阅读器墨色，浅色 App 主题下也可读。
class _PageTurnSwitch extends ConsumerWidget {
  const _PageTurnSwitch();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(
      settingsProvider.select((settings) => settings.pageTurnAnimation),
    );
    return AppSwitch.adaptive(
      value: enabled,
      semanticLabel: '翻页动画',
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      activeTrackColor: AppColors.darkPrimary,
      activeThumbColor: AppColors.readerInk,
      inactiveTrackColor: AppColors.readerInk.withValues(alpha: .22),
      inactiveThumbColor: AppColors.readerInk,
      onChanged: (value) => unawaited(
        ref.read(settingsProvider.notifier).setPageTurnAnimation(value),
      ),
    );
  }
}
