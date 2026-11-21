import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/di/providers.dart';
import '../../core/icons/app_icons.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/ui/glass/app_glass.dart';
import '../../data/local/settings_store.dart';
import '../../data/sources/pdf_reader_channel.dart';
import '../reader/reader_mode.dart';
import '../reader/widgets/page_turn_view.dart';
import '../reader/widgets/reader_hud.dart';
import '../reader/widgets/reader_tap_zones.dart';
import '../reader/widgets/scroll_reader_view.dart';

/// 内置 PDF 阅读器入参（`/pdf?uri=...&title=...`）。
class PdfViewerArgs {
  const PdfViewerArgs({required this.uri, this.title = ''});

  final String uri;
  final String title;

  factory PdfViewerArgs.fromQuery(Map<String, String> query) => PdfViewerArgs(
        uri: query['uri'] ?? '',
        title: query['title'] ?? '',
      );

  Map<String, String> toQuery() => <String, String>{
        'uri': uri,
        if (title.isNotEmpty) 'title': title,
      };

  String get route => '/pdf?${Uri(queryParameters: toQuery()).query}';

  String get displayTitle => title.trim().isEmpty ? 'PDF' : title.trim();
}

/// 用系统自带的 PdfRenderer 阅读本地下载的 PDF：左右翻页 / 上下滚动 + 缩放 + HUD 进度条。
///
/// HUD 里可以随时切换阅读模式（顶部图标 / 模式文字按钮，两处都打开同一个选择面板）。
class PdfViewerPage extends ConsumerStatefulWidget {
  const PdfViewerPage({required this.args, super.key});

  final PdfViewerArgs args;

  @override
  ConsumerState<PdfViewerPage> createState() => _PdfViewerPageState();
}

class _PdfViewerPageState extends ConsumerState<PdfViewerPage>
    with SingleTickerProviderStateMixin {
  static const int _cacheLimit = 12;

  late final PdfReader _reader;
  late final PageController _pageController = PageController();
  late final ScrollController _scrollController = ScrollController();
  late final AnimationController _bounceController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
  );

  final Map<int, Uint8List> _rendered = <int, Uint8List>{};
  final Set<int> _rendering = <int>{};
  final Set<int> _failed = <int>{};
  final Map<int, TransformationController> _zoom = {};

  PdfDocumentInfo? _info;
  String? _error;
  ReaderMode _mode = ReaderMode.paged;
  int _page = 1;
  int? _dragPage;
  int _renderWidth = 1080;
  bool _hudVisible = true;
  bool _hudPickerOpen = false;
  bool _locked = false;
  double _bounceOffset = 0;
  Timer? _hudTimer;

  int get _total => _info?.pageCount ?? 0;

  @override
  void initState() {
    super.initState();
    _reader = ref.read(pdfReaderProvider);
    _bounceController.addListener(() {
      setState(() {
        _bounceOffset = math.sin(_bounceController.value * math.pi) * 8;
      });
    });
    unawaited(_open());
    _restartHudTimer();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final media = MediaQuery.of(context);
    _renderWidth =
        (media.size.width * media.devicePixelRatio).round().clamp(720, 1600);
  }

  @override
  void dispose() {
    _hudTimer?.cancel();
    unawaited(_reader.close());
    for (final controller in _zoom.values) {
      controller.dispose();
    }
    _pageController.dispose();
    _scrollController.dispose();
    _bounceController.dispose();
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    super.dispose();
  }

  // ---------------------------------------------------------------- 加载
  Future<void> _open() async {
    setState(() {
      _error = null;
      _info = null;
      _rendered.clear();
      _failed.clear();
    });
    try {
      final info = await _reader.open(widget.args.uri);
      if (!mounted) return;
      if (info.isEmpty) {
        setState(() => _error = '这个 PDF 没有可显示的页面');
        return;
      }
      setState(() => _info = info);
      await _ensure(0);
      _prefetchAround(1);
      unawaited(
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '$error');
    }
  }

  Future<void> _ensure(int index) async {
    if (_info == null || index < 0 || index >= _total) return;
    if (_rendered.containsKey(index) || _rendering.contains(index)) return;
    _rendering.add(index);
    try {
      final bytes = await _reader.render(widget.args.uri, index, _renderWidth);
      if (bytes != null && bytes.isNotEmpty) {
        _rendered[index] = bytes;
        _failed.remove(index);
        _evict();
      } else if (mounted) {
        _failed.add(index);
      }
    } catch (_) {
      if (mounted) _failed.add(index);
    } finally {
      if (mounted) {
        _rendering.remove(index);
        setState(() {});
      }
    }
  }

  /// 只保留离当前页最近的若干页，1200 页的 PDF 也不会把内存吃穿。
  void _evict() {
    if (_rendered.length <= _cacheLimit) return;
    final keys = _rendered.keys.toList()
      ..sort((a, b) => (b - _page).abs().compareTo((a - _page).abs()));
    for (final key in keys.take(_rendered.length - _cacheLimit)) {
      _rendered.remove(key);
    }
  }

  void _prefetchAround(int page) {
    for (var offset = 0; offset <= 2; offset++) {
      final next = page - 1 + offset;
      if (next >= 0 && next < _total) unawaited(_ensure(next));
    }
  }

  // ---------------------------------------------------------------- 翻页
  void _goToPage(int page, {bool? animate, bool bounceAtEdge = true}) {
    final target = page.clamp(1, math.max(1, _total)).toInt();
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
    _restartHudTimer();
    _prefetchAround(target);
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

  void _toggleHud() {
    setState(() => _hudVisible = !_hudVisible);
    unawaited(
      SystemChrome.setEnabledSystemUIMode(
        _hudVisible ? SystemUiMode.edgeToEdge : SystemUiMode.immersiveSticky,
      ),
    );
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
    });
  }

  /// HUD 里的「阅读模式」入口：显式给两个选项，而不是一个图标来回猜。
  Future<void> _pickMode(BuildContext controlsContext) async {
    _hudTimer?.cancel();
    final selected = await AppSheet.show<ReaderMode>(
      context: controlsContext,
      showDragHandle: true,
      backgroundColor: AppColors.darkSurfaceContainer,
      builder: (sheetContext) => ReaderControlsTheme(
        child: SafeArea(
          child: _modePicker((mode) => Navigator.of(sheetContext).pop(mode)),
        ),
      ),
    );
    if (!mounted) return;
    if (selected == null || selected == _mode) {
      _restartHudTimer();
      return;
    }
    _applyMode(selected);
  }

  Widget _buildGlassModePicker(BuildContext context, VoidCallback close) =>
      Padding(
        padding: const EdgeInsets.only(top: 14),
        child: _modePicker((mode) {
          close();
          if (mode != _mode) _applyMode(mode);
        }),
      );

  Widget _modePicker(ValueChanged<ReaderMode> onSelect) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
            child: Text(
              '阅读模式',
              style: AppTypography.sectionTitle
                  .copyWith(color: AppColors.readerInk),
            ),
          ),
          for (final mode in ReaderMode.values)
            AppListTile(
              leading: SvgIcon(mode.icon, size: 20, color: AppColors.readerInk),
              title: Text(
                mode.label,
                style: AppTypography.body.copyWith(color: AppColors.readerInk),
              ),
              trailing: mode == _mode
                  ? const SvgIcon(AppIcons.check,
                      size: 20, color: AppColors.darkPrimary,)
                  : null,
              onTap: () => onSelect(mode),
            ),
          const SizedBox(height: 8),
        ],
      );

  void _applyMode(ReaderMode next) {
    final ratio = _total <= 1 ? 0.0 : (_page - 1) / (_total - 1);
    setState(() {
      _mode = next;
      _hudVisible = true;
    });
    _restartHudTimer();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (next == ReaderMode.paged) {
        if (_pageController.hasClients) _pageController.jumpToPage(_page - 1);
      } else if (_scrollController.hasClients) {
        _scrollController
            .jumpTo(ratio * _scrollController.position.maxScrollExtent);
      }
      _prefetchAround(_page);
    });
  }

  void _setLocked(bool locked) {
    if (_locked == locked) return;
    setState(() => _locked = locked);
    if (!locked) _restartHudTimer();
  }

  void _exit() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/history');
    }
  }

  TransformationController _zoomOf(int page) =>
      _zoom.putIfAbsent(page, TransformationController.new);

  void _toggleZoomCurrent() {
    final controller = _zoomOf(_page);
    if (controller.value.getMaxScaleOnAxis() > 1.01) {
      controller.value = Matrix4.identity();
      return;
    }
    controller.value = Matrix4.identity()..scale(2.2);
  }

  // ---------------------------------------------------------------- UI
  @override
  Widget build(BuildContext context) => ReaderControlsTheme(
        child: Builder(builder: _buildViewer),
      );

  Widget _buildViewer(BuildContext context) {
    final error = _error;
    if (error != null) return _buildError(error);
    final info = _info;
    if (info == null) {
      return const Scaffold(
        backgroundColor: AppColors.readerBg,
        body: Center(
          child: AppProgressIndicator.circular(color: AppColors.readerInk),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.readerBg,
      body: Stack(
        children: <Widget>[
          Positioned.fill(
            child: Transform.translate(
              offset: Offset(_bounceOffset, 0),
              child: _buildBody(),
            ),
          ),
          Positioned.fill(
            child: ReaderHud(
              title: widget.args.displayTitle,
              page: _dragPage ?? _page,
              total: _total,
              mode: _mode,
              visible: _hudVisible,
              // HUD 右侧的模式按钮：显示当前模式名，点开就是模式选择面板。
              lineLabel: _mode.label,
              onSwitchLine: () => _pickMode(context),
              glassPickerBuilder: _buildGlassModePicker,
              onGlassPickerOpenChanged: (open) {
                _hudPickerOpen = open;
                _restartHudTimer();
              },
              onExit: _exit,
              onToggleMode: () => _pickMode(context),
              onJump: _commitHudSeek,
              onSliderCancel: () {
                if (_dragPage != null) setState(() => _dragPage = null);
              },
              onSliderChanged: (value) {
                setState(() {
                  _dragPage = value.round().clamp(1, _total).toInt();
                });
                _restartHudTimer();
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_mode == ReaderMode.paged) {
      return ReaderTapZones(
        enabled: !_locked,
        onDoubleTap: _toggleZoomCurrent,
        onPrevious: () => _goToPage(_page - 1),
        onNext: () => _goToPage(_page + 1),
        onToggleHud: _toggleHud,
        child: PageTurnView(
          controller: _pageController,
          total: _total,
          physics: _locked ? const NeverScrollableScrollPhysics() : null,
          onPageChanged: (page) {
            if (page == _page) return;
            setState(() {
              _page = page;
              _dragPage = null;
            });
            _prefetchAround(page);
          },
          itemBuilder: (context, index) => _PdfZoom(
            controller: _zoomOf(index + 1),
            onInteractionChanged: _setLocked,
            child: _pageImage(index),
          ),
        ),
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: _toggleHud,
      onDoubleTap: _toggleZoomCurrent,
      child: ScrollReaderView(
        controller: _scrollController,
        total: _total,
        physics: _locked ? const NeverScrollableScrollPhysics() : null,
        onPageChanged: (page) {
          if (page == _page) return;
          setState(() {
            _page = page;
            _dragPage = null;
          });
          _prefetchAround(page);
        },
        itemBuilder: (context, index) => _PdfZoom(
          controller: _zoomOf(index + 1),
          onInteractionChanged: _setLocked,
          child: _pageImage(index),
        ),
      ),
    );
  }

  Widget _pageImage(int index) {
    final bytes = _rendered[index];
    if (bytes != null) {
      return Center(
        child: Image.memory(
          bytes,
          fit: BoxFit.contain,
          gaplessPlayback: true,
          filterQuality: FilterQuality.medium,
        ),
      );
    }
    if (_failed.contains(index)) {
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
              '第 ${index + 1} 页渲染失败',
              style: AppTypography.caption.copyWith(color: AppColors.readerInk),
            ),
            const SizedBox(height: 8),
            AppButton.text(
              onPressed: () {
                _failed.remove(index);
                unawaited(_ensure(index));
              },
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }
    // 首次构建时排一次渲染（不能直接在 build 里 setState）。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_ensure(index));
    });
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

  Widget _buildError(String message) {
    return Scaffold(
      backgroundColor: AppColors.readerBg,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Align(
              alignment: Alignment.centerLeft,
              child: AppIconButton(
                tooltip: '返回',
                onPressed: _exit,
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
                        '打不开这个 PDF',
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
                      AppButton(
                        onPressed: () => unawaited(_open()),
                        child: const Text('重试'),
                      ),
                      const SizedBox(height: 10),
                      AppButton.text(
                        onPressed: () async {
                          await ref.read(downloadRepositoryProvider).openFile(
                                uri: widget.args.uri,
                                name: widget.args.title,
                              );
                        },
                        child: const Text('用其它应用打开'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// PDF 页缩放：与漫画阅读器同一套（双指捏合 / 双指按下即锁翻页）。
class _PdfZoom extends StatefulWidget {
  const _PdfZoom({
    required this.controller,
    required this.child,
    required this.onInteractionChanged,
  });

  final TransformationController controller;
  final Widget child;
  final ValueChanged<bool> onInteractionChanged;

  @override
  State<_PdfZoom> createState() => _PdfZoomState();
}

class _PdfZoomState extends State<_PdfZoom> {
  bool _zoomed = false;
  int _pointers = 0;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTransformChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTransformChanged);
    super.dispose();
  }

  bool get _locked => _zoomed || _pointers >= 2;

  void _report() => widget.onInteractionChanged(_locked);

  void _onTransformChanged() {
    final zoomed = widget.controller.value.getMaxScaleOnAxis() > 1.01;
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
        maxScale: 4,
        panEnabled: _zoomed,
        onInteractionEnd: (_) {
          if (widget.controller.value.getMaxScaleOnAxis() <= 1.01) {
            widget.controller.value = Matrix4.identity();
          }
        },
        child: widget.child,
      ),
    );
  }
}
