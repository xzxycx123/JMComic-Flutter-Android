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
import '../../data/local/endpoint_store.dart';
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
      body: data.when(
        loading: () => Center(
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
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
            child: IconButton(
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
                    FilledButton(onPressed: onRetry, child: const Text('重试')),
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
  AlbumRepository? _repository;
  late ReaderMode _mode;
  late int _page;
  bool _hudVisible = true;
  bool _zoomed = false;
  bool _switchingLine = false;
  Timer? _hudTimer;
  DateTime _lastProgressWrite = DateTime.fromMillisecondsSinceEpoch(0);
  double _bounceOffset = 0;

  int get _total => widget.data.total;

  @override
  void initState() {
    super.initState();
    _mode = widget.data.mode;
    _page = widget.data.initialPage;
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
    unawaited(_persistProgress());
    unawaited(_applySystemUi(false));
    super.dispose();
  }

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
  void _goToPage(int page, {bool animate = true}) {
    final target = page.clamp(1, _total == 0 ? 1 : _total).toInt();
    if (target == _page) {
      if (target <= 1 || target >= _total) {
        _bounceController.forward(from: 0);
        HapticFeedback.lightImpact();
      }
      return;
    }
    setState(() => _page = target);
    _loader.setFocus(target);
    unawaited(_persistProgress(throttle: true));
    _restartHudTimer();

    if (_mode == ReaderMode.paged) {
      if (animate) {
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

  Future<void> _persistProgress({bool throttle = false}) async {
    final repository = _repository;
    if (repository == null) return;
    if (throttle &&
        DateTime.now().difference(_lastProgressWrite) <
            AppConfig.progressWriteThrottle) {
      return;
    }
    _lastProgressWrite = DateTime.now();
    await repository.saveProgress(
      widget.data.args.albumId,
      widget.data.args.chapterId,
      _page,
      _total,
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

  void _exit() {
    unawaited(_persistProgress());
    _safePop(context);
  }

  // ---------------------------------------------------------------- 分流
  String get _lineLabel =>
      JmConstants.lineLabelOf(ref.read(jmApiProvider).apiHost);

  /// 顶栏「分流」菜单：切换 API 线路 -> 重新 /setting 取该线路图床 -> 清缓存按当前页重载。
  Future<void> _pickLine() async {
    final api = ref.read(jmApiProvider);
    final store = ref.read(endpointStoreProvider);
    final current = api.apiHost;
    // 当前线路置顶；其余已收录分流（线路1..5）按顺序，最后是其它/手填线路。
    final hosts = <String>[...api.availableHosts]..sort((a, b) {
        if (a == current) return -1;
        if (b == current) return 1;
        final rank =
            JmConstants.lineRankOf(a).compareTo(JmConstants.lineRankOf(b));
        if (rank != 0) return rank;
        return api.availableHosts
            .indexOf(a)
            .compareTo(api.availableHosts.indexOf(b));
      });
    if (hosts.isEmpty) return;

    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.darkSurfaceContainer,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(sheetContext).size.height * 0.62,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
                  child: Text(
                    '切换分流',
                    style: AppTypography.sectionTitle
                        .copyWith(color: AppColors.readerInk),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    'JMComic 常用 4 条分流（线路1-4）；切换后重新拉 /setting 取该线路图床，并按当前页重载',
                    style: AppTypography.micro.copyWith(
                      color: AppColors.readerInk.withValues(alpha: 0.65),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: <Widget>[
                      for (final host in hosts)
                        _LineTile(
                          host: host,
                          current: host == current,
                          health: store.healthOf(host),
                          onTap: () => Navigator.of(sheetContext).pop(host),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );

    if (selected == null || selected == current || !mounted) return;

    setState(() => _switchingLine = true);
    final messenger = ScaffoldMessenger.of(context);
    final ok = await api.switchApiHost(selected);
    if (!mounted) return;
    setState(() => _switchingLine = false);
    if (!ok) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('${JmConstants.lineLabelOf(selected)} 不可用，已保留原线路'),
        ),
      );
      return;
    }
    // 换线后旧线路的图片作废：清缓存 + 按当前页重新预取。
    _loader.clear();
    _loader.setFocus(_page);
    messenger.showSnackBar(
      SnackBar(content: Text('已切到 ${JmConstants.lineLabelOf(selected)}')),
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
              page: _page,
              total: _total,
              mode: _mode,
              visible: _hudVisible,
              lineLabel: _lineLabel,
              switchingLine: _switchingLine,
              onSwitchLine: _pickLine,
              onExit: _exit,
              onToggleMode: _toggleMode,
              onJump: (page) => _goToPage(page),
              onSliderChanged: (value) {
                setState(() => _page = value.round().clamp(1, _total).toInt());
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
        enabled: !_zoomed,
        onPrevious: _previousPage,
        onNext: _nextPage,
        onToggleHud: _toggleHud,
        child: PageTurnView(
          controller: _pageController,
          total: _total,
          onPageChanged: (page) {
            if (page == _page) return;
            setState(() => _page = page);
            _loader.setFocus(page);
            unawaited(_persistProgress(throttle: true));
          },
          itemBuilder: (context, index) => _ZoomablePage(
            onZoomChanged: (zoomed) {
              if (_zoomed == zoomed) return;
              setState(() => _zoomed = zoomed);
            },
            child: _pageContent(index + 1),
          ),
        ),
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: _toggleHud,
      child: ScrollReaderView(
        controller: _scrollController,
        total: _total,
        onPageChanged: (page) {
          if (page == _page) return;
          setState(() => _page = page);
          _loader.setFocus(page);
          unawaited(_persistProgress(throttle: true));
        },
        itemBuilder: (context, index) => _pageContent(index + 1),
      ),
    );
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
            TextButton(
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
        child: CircularProgressIndicator(
          strokeWidth: 2.4,
          color: AppColors.readerInk,
        ),
      ),
    );
  }
}

/// 单页缩放：双击 1.0 <-> 2.0，并把缩放状态回传给外层以禁用三分区点击。
class _ZoomablePage extends StatefulWidget {
  const _ZoomablePage({required this.child, required this.onZoomChanged});

  final Widget child;
  final ValueChanged<bool> onZoomChanged;

  @override
  State<_ZoomablePage> createState() => _ZoomablePageState();
}

class _ZoomablePageState extends State<_ZoomablePage> {
  final TransformationController _controller = TransformationController();
  bool _zoomed = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggleZoom() {
    setState(() {
      _zoomed = !_zoomed;
      _controller.value =
          _zoomed ? (Matrix4.identity()..scale(2.0)) : Matrix4.identity();
    });
    widget.onZoomChanged(_zoomed);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onDoubleTap: _toggleZoom,
      child: InteractiveViewer(
        transformationController: _controller,
        minScale: 1,
        maxScale: 3,
        onInteractionUpdate: (details) {
          final next = details.scale > 1.01;
          if (next != _zoomed) {
            setState(() => _zoomed = next);
            widget.onZoomChanged(next);
          }
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
    return ListTile(
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
              child: Text(
                '当前',
                style: AppTypography.micro
                    .copyWith(color: AppColors.darkOnPrimaryContainer),
              ),
            ),
          ],
        ],
      ),
      subtitle: Text(
        host,
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
