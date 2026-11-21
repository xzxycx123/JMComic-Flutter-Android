import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/app_config.dart';
import '../../core/constants/jm_constants.dart';
import '../../core/di/providers.dart';
import '../../core/icons/app_icons.dart';
import '../../core/icons/app_images.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/ui/app_toast.dart';
import '../../core/ui/glass/app_glass.dart';
import '../../data/local/endpoint_store.dart';
import '../../data/local/progress_store.dart';
import '../../data/local/settings_store.dart';
import '../../data/repositories/album_repository.dart';
import 'reader_mode.dart';
import 'reader_page_loader.dart';
import 'reader_providers.dart';
import 'widgets/page_turn_view.dart';
import 'widgets/reader_hud.dart';
import 'widgets/reader_tap_zones.dart';
import 'widgets/scroll_reader_view.dart';

/// 阅读器：双模式（左右翻页 / 上下滚动）+ 三分区点击 + HUD + 进度记忆。
class ReaderPage extends ConsumerWidget {
  const ReaderPage({required this.args, super.key});

  final ReaderArgs args;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(readerDataProvider(args));

    return Scaffold(
      backgroundColor: AppColors.readerBg,
      body: ReaderControlsTheme(
        child: data.when(
          loading: () => Center(
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
          ),
          error: (error, stackTrace) => _ReaderError(
            message: '$error',
            onRetry: () => ref.invalidate(readerDataProvider(args)),
            onExit: () => _safePop(context),
          ),
          data: (value) => _ReaderScaffold(data: value),
        ),
      ),
    );
  }
}

void _safePop(BuildContext context) {
  if (context.canPop()) {
    context.pop();
  } else {
    context.go('/');
  }
}

class _ReaderError extends StatelessWidget {
  const _ReaderError({
    required this.message,
    required this.onRetry,
    required this.onExit,
  });

  final String message;
  final VoidCallback onRetry;
  final VoidCallback onExit;

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
                    AppButton(onPressed: onRetry, child: const Text('重试')),
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

class _ReaderScaffold extends ConsumerStatefulWidget {
  const _ReaderScaffold({required this.data});

  final ReaderData data;

  @override
  ConsumerState<_ReaderScaffold> createState() => _ReaderScaffoldState();
}

class _ReaderScaffoldState extends ConsumerState<_ReaderScaffold>
    with SingleTickerProviderStateMixin {
  late final PageController _pageController;
  late final ScrollController _scrollController;
  late final AnimationController _bounceController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
  );

  late final ReaderPageLoader _loader;

  /// 进度落盘器（串行化 + 最后一次写入优先）。initState 里取好，dispose 也能直接用。
  late final ProgressRecorder _recorder;
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
  bool _hudPickerOpen = false;
  Timer? _hudTimer;
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

  int get _total => widget.data.total;

  @override
  void initState() {
    super.initState();
    _mode = widget.data.mode;
    _page = widget.data.initialPage;
    _recorder = ref.read(readerProgressRecorderProvider);
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
    unawaited(_applySystemUi(true));
    // 进入阅读器就排队：当前页 + 后续 5 页 + 回看 2 页，槽位空出来自动补位。
    _loader.setFocus(_page);
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
    // 任何退出路径（HUD / 系统返回 / 侧滑手势 / 路由被替换）都在这里兜一次：
    // 同步取快照入队，再尽力 flush 落盘，不依赖 widget 树还活着。
    unawaited(_persistProgress());
    unawaited(_recorder.flush());
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
    final repository = await _repositoryInstance();
    return repository.loadPage(
      photoId: widget.data.args.chapterId,
      filename: widget.data.chapter.images[page - 1],
      scrambleIdOverride: widget.data.scrambleId,
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
    final target = clampReaderPage(page, _total);
    if (target == _page) {
      if (bounceAtEdge && (target <= 1 || target >= _total)) {
        _bounceController.forward(from: 0);
        HapticFeedback.lightImpact();
      }
      return;
    }
    setState(() {
      _page = target;
      _dragPage = null;
    });
    _loader.setFocus(target);
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
      final ratio = _total <= 1 ? 0.0 : (target - 1) / (_total - 1);
      _scrollController
          .jumpTo(ratio * _scrollController.position.maxScrollExtent);
    }
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
    if (_page >= _total) {
      _bounceController.forward(from: 0);
      HapticFeedback.lightImpact();
      return;
    }
    _goToPage(_page + 1);
  }

  /// 当前阅读位置的快照：同步取值，不依赖 widget 树 / 仓储是否就绪。
  ///
  /// `total == 0`（空章节，没有任何可读页）时返回 null：不写脏进度。
  ProgressSnapshot? _progressSnapshot() {
    final total = _total;
    if (total <= 0) return null;
    return ProgressSnapshot(
      albumId: widget.data.args.albumId,
      chapterId: widget.data.args.chapterId,
      page: clampReaderPage(_page, total),
      total: total,
      // 阅读历史页直接用这里记下的标题，不再逐条请求详情。
      albumTitle: widget.data.args.albumTitle,
      chapterTitle: widget.data.title,
    );
  }

  /// 落盘当前进度。
  ///
  /// 不再走 `_repository`（仓储还没初始化的退出路径会把进度直接丢掉）：
  /// 直接交给 [ProgressRecorder]，由它串行化 + 最后一次写入优先地写进 ProgressStore。
  Future<void> _persistProgress({bool throttle = false}) async {
    final snapshot = _progressSnapshot();
    if (snapshot == null) return;
    if (throttle &&
        DateTime.now().difference(_lastProgressWrite) <
            AppConfig.progressWriteThrottle) {
      return;
    }
    _lastProgressWrite = DateTime.now();
    await _recorder.record(snapshot);
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
    if (!_hudVisible || _hudPickerOpen) return;
    _hudTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      setState(() => _hudVisible = false);
      unawaited(_applySystemUi(true));
    });
  }

  void _toggleMode() {
    final next = _mode.toggled;
    final ratio = _total <= 1 ? 0.0 : (_page - 1) / (_total - 1);
    setState(() {
      _mode = next;
      _hudVisible = true;
      // 换模式时把竖读整屏缩放归位，避免残留的放大/平移带到另一种模式。
      _verticalScale = 1;
      _verticalOffset = Offset.zero;
    });
    unawaited(
      ref
          .read(readerDataProvider(widget.data.args).notifier)
          .rememberMode(next),
    );
    _restartHudTimer();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (next == ReaderMode.paged) {
        if (_pageController.hasClients) _pageController.jumpToPage(_page - 1);
      } else if (_scrollController.hasClients) {
        _scrollController
            .jumpTo(ratio * _scrollController.position.maxScrollExtent);
      }
    });
  }

  /// HUD 退出：先把当前页落盘（尽量 await），再弹栈。
  Future<void> _exit() async {
    await _persistProgress();
    await _recorder.flush();
    if (!mounted) return;
    _safePop(context);
  }

  /// 系统返回 / 侧滑返回：先同步取快照入队，再尽力 flush。
  void _handleSystemPop(bool didPop) {
    unawaited(_persistProgress());
    if (didPop) unawaited(_recorder.flush());
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

  Widget _buildGlassLinePicker(BuildContext context, VoidCallback close) =>
      _linePicker(
        context,
        hosts: _lineChoices(),
        onSelect: (host) {
          close();
          unawaited(_applyLine(host));
        },
      );

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
      canPop: true,
      // 系统返回键 / 侧滑手势：didPop 时弹栈已开始，这里同步取快照入队并 flush，
      // 不依赖 HUD 退出按钮（dispose 还会再兜一次）。
      onPopInvokedWithResult: (didPop, result) => _handleSystemPop(didPop),
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
              title: widget.data.title,
              // 拖动进度条时显示预览页，松手才真正翻页。
              page: _dragPage ?? _page,
              total: _total,
              mode: _mode,
              visible: _hudVisible,
              lineLabel: _lineLabel,
              switchingLine: _switchingLine,
              onSwitchLine: _pickLine,
              glassPickerBuilder: _buildGlassLinePicker,
              glassPickerHeight: 52 + _lineChoices().length * 72.0,
              onGlassPickerOpenChanged: (open) {
                _hudPickerOpen = open;
                _restartHudTimer();
              },
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
        // 缩放中只关单击（防误翻页），双击仍可缩回 1.0。
        enabled: !_locked,
        onDoubleTap: _toggleZoomCurrent,
        onPrevious: _previousPage,
        onNext: _nextPage,
        onToggleHud: _toggleHud,
        child: PageTurnView(
          controller: _pageController,
          total: _total,
          // 缩放中把横向拖动让给图片平移，否则会一边放大一边翻页。
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
          itemBuilder: (context, index) => _ZoomablePage(
            controller: _zoomControllerOf(index + 1),
            onInteractionChanged: _setLocked,
            child: _pageContent(index + 1),
          ),
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
        onTap: _toggleHud,
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
            itemBuilder: (context, index) => _pageContent(index + 1),
          ),
        ),
      ),
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

  Widget _pageContent(int page) => _pageImage(page);

  Widget _pageImage(int page) {
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
            AppButton.text(
              onPressed: () {
                _loader.request(page);
              },
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
