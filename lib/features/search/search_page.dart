import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/jm_constants.dart';
import '../../core/icons/app_icons.dart';
import '../../core/theme/app_typography.dart';
import '../../core/ui/glass/app_glass.dart';
import '../home/widgets/feed_skeleton.dart';
import 'search_providers.dart';
import 'widgets/result_grid.dart';
import 'widgets/search_field.dart';

/// 搜索页：车号直达详情 / 关键词走 GET /search（PLAN §7.4）。
class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key, this.initialQuery, this.forceKeyword = false});

  final String? initialQuery;
  final bool forceKeyword;

  static String keywordLocation(String tag) => Uri(
        path: '/search',
        queryParameters: {'q': tag, 'mode': 'keyword'},
      ).toString();

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  /// 累计位移超过该值才切换，避免轻微抖动让顶部反复闪动。
  static const double _chromeToggleThreshold = 12;

  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  String _liveHint = '输入车号或关键词';
  String? _forcedQuery;

  /// 顶部区块（搜索框 + 排序条）是否展开：向下滚动收起，向上滚动恢复。
  bool _chromeVisible = true;
  double _chromeScrollDelta = 0;

  @override
  void initState() {
    super.initState();
    _applyRouteQuery();
  }

  @override
  void didUpdateWidget(covariant SearchPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialQuery != widget.initialQuery ||
        oldWidget.forceKeyword != widget.forceKeyword) {
      _applyRouteQuery();
    }
  }

  void _applyRouteQuery() {
    final query = widget.initialQuery?.trim() ?? '';
    _forcedQuery = widget.forceKeyword && query.isNotEmpty ? query : null;
    _controller.text = query;
    _liveHint = resolveQuery(query, forceKeyword: _forcedQuery != null).hint;
    if (query.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _controller.text == query) _submit(query);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _setChromeVisible(bool visible) {
    if (_chromeVisible == visible || !mounted) return;
    // 收起搜索框时一并收键盘，避免输入法把内容顶起。
    if (!visible) _focusNode.unfocus();
    setState(() => _chromeVisible = visible);
  }

  void _trackScrollDirection(double delta, ScrollMetrics metrics) {
    if (delta == 0) return;
    if (metrics.pixels <= 0) {
      _chromeScrollDelta = 0;
      _setChromeVisible(true);
      return;
    }
    if ((delta > 0) != (_chromeScrollDelta > 0)) {
      _chromeScrollDelta = delta;
    } else {
      _chromeScrollDelta += delta;
    }
    if (_chromeScrollDelta >= _chromeToggleThreshold) {
      _chromeScrollDelta = 0;
      _setChromeVisible(false);
    } else if (_chromeScrollDelta <= -_chromeToggleThreshold) {
      _chromeScrollDelta = 0;
      _setChromeVisible(true);
    }
  }

  bool _handleScroll(ScrollNotification notification) {
    // 排序条的横向列表、嵌套滚动都忽略，只跟随结果区的纵向滚动。
    if (notification.depth != 0) return false;
    if (notification.metrics.axis != Axis.vertical) return false;

    if (notification is ScrollUpdateNotification) {
      _trackScrollDirection(
        notification.scrollDelta ?? 0,
        notification.metrics,
      );
    } else if (notification is OverscrollNotification) {
      // 顶部继续下拉时始终露出搜索框。
      if (notification.overscroll < 0) _setChromeVisible(true);
    } else if (notification is ScrollStartNotification ||
        notification is ScrollEndNotification) {
      _chromeScrollDelta = 0;
    }
    return false;
  }

  void _onChanged(String value) {
    if (_forcedQuery != value.trim()) _forcedQuery = null;
    final query = resolveQuery(value, forceKeyword: _forcedQuery != null);
    setState(() => _liveHint = query.hint);
  }

  void _submit(String value) {
    final decision =
        resolveQuery(value, forceKeyword: _forcedQuery == value.trim());
    if (decision.isEmpty) return;
    if (decision.isAlbum) {
      _focusNode.unfocus();
      context.push('/album/${decision.albumId}');
      return;
    }
    _focusNode.unfocus();
    _chromeScrollDelta = 0;
    _setChromeVisible(true);
    unawaited(
      ref.read(searchControllerProvider.notifier).search(decision.keyword!),
    );
  }

  void _fillHistory(String keyword) {
    _forcedQuery = keyword.trim();
    _controller.text = keyword;
    _onChanged(keyword);
    _submit(keyword);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final resultState = ref.watch(searchControllerProvider);
    final history = ref.watch(searchHistoryProvider);

    return AppGlassPage(
      body: SafeArea(
        child: Column(
          children: <Widget>[
            _CollapsibleChrome(
              visible: _chromeVisible,
              child: Column(
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: SearchField(
                      controller: _controller,
                      focusNode: _focusNode,
                      autofocus: widget.initialQuery?.trim().isNotEmpty != true,
                      onChanged: _onChanged,
                      onSubmitted: _submit,
                      onCancel: () {
                        ref.read(searchControllerProvider.notifier).reset();
                        if (context.canPop()) {
                          context.pop();
                        } else {
                          context.go('/');
                        }
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 2, 20, 6),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        _liveHint,
                        style: AppTypography.micro
                            .copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: NotificationListener<ScrollNotification>(
                onNotification: _handleScroll,
                child: resultState.when(
                  loading: () => const Center(
                    child: SizedBox(
                      width: 26,
                      height: 26,
                      child: AppProgressIndicator.circular(strokeWidth: 2.4),
                    ),
                  ),
                  error: (error, stackTrace) => EmptyState(
                    illustration: AppIllustrations.errorNetwork,
                    title: '搜索失败',
                    description: '$error',
                    actionLabel: '重试',
                    onAction: () => _submit(_controller.text),
                  ),
                  data: (results) {
                    if (results == null) {
                      return _IdleBody(
                        history: history,
                        onSelectHistory: _fillHistory,
                        onClearHistory: () =>
                            ref.read(searchHistoryProvider.notifier).clear(),
                        onRemoveHistory: (keyword) => ref
                            .read(searchHistoryProvider.notifier)
                            .remove(keyword),
                        onSelectHot: _fillHistory,
                      );
                    }
                    if (results.isEmpty) {
                      return EmptyState(
                        illustration: AppIllustrations.emptySearch,
                        title: '没有相关本子',
                        description: '换个关键词试试，或直接输入车号',
                        actionLabel: '换个关键词',
                        onAction: () {
                          _controller.clear();
                          _onChanged('');
                          _focusNode.requestFocus();
                        },
                      );
                    }
                    return Column(
                      children: <Widget>[
                        ResultHeader(
                          total: results.total,
                          keyword: results.keyword,
                        ),
                        _CollapsibleChrome(
                          visible: _chromeVisible,
                          child: _SortBar(
                            selected: results.order,
                            onSelected: (order) => ref
                                .read(searchControllerProvider.notifier)
                                .setSort(order),
                          ),
                        ),
                        Expanded(
                          child: ResultGrid(
                            items: results.items,
                            loadingMore: results.loadingMore,
                            error: results.error,
                            onRetry: () => ref
                                .read(searchControllerProvider.notifier)
                                .loadMore(),
                            onLoadMore: () => ref
                                .read(searchControllerProvider.notifier)
                                .loadMore(),
                            onTap: (album) =>
                                context.push('/album/${album.id}'),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 顶部区块折叠容器：向下滚动时把区块高度收成 0，向上滚动再展开。
class _CollapsibleChrome extends StatefulWidget {
  const _CollapsibleChrome({required this.visible, required this.child});

  final bool visible;
  final Widget child;

  @override
  State<_CollapsibleChrome> createState() => _CollapsibleChromeState();
}

class _CollapsibleChromeState extends State<_CollapsibleChrome> {
  static const Duration _duration = Duration(milliseconds: 220);

  /// 折叠 / 展开过程要裁剪溢出内容；完全展开后放开裁剪，
  /// 免得把液玻璃按钮的外发光也切掉。
  bool _clipping = false;

  @override
  void didUpdateWidget(covariant _CollapsibleChrome oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.visible != widget.visible) _clipping = true;
  }

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      excluding: !widget.visible,
      child: ClipRect(
        clipBehavior: _clipping ? Clip.hardEdge : Clip.none,
        child: AnimatedAlign(
          alignment: Alignment.topCenter,
          heightFactor: widget.visible ? 1 : 0,
          curve: Curves.easeOutCubic,
          duration: _duration,
          onEnd: () {
            if (widget.visible && _clipping) {
              setState(() => _clipping = false);
            }
          },
          child: widget.child,
        ),
      ),
    );
  }
}

/// 搜索结果排序条：时间 / 阅读数 / 人气 / 最新上架（服务端 `o` 参数）。
class _SortBar extends StatelessWidget {
  const _SortBar({required this.selected, required this.onSelected});

  final AlbumOrder selected;
  final ValueChanged<AlbumOrder> onSelected;

  static const Map<AlbumOrder, String> _labels = <AlbumOrder, String>{
    AlbumOrder.latestUpdate: '最新更新',
    AlbumOrder.mostViewed: '阅读数',
    AlbumOrder.popular: '人气',
    AlbumOrder.newest: '最新上架',
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 52,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        clipBehavior: context.isLiquidGlass ? Clip.none : Clip.hardEdge,
        padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
        itemCount: kSearchSorts.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final order = kSearchSorts[index];
          final active = order == selected;
          void select() => onSelected(order);
          final foreground =
              active ? scheme.onPrimary : scheme.onSurfaceVariant;
          final label = Text(
            _labels[order] ?? order.label,
            style: AppTypography.micro.copyWith(
              color: foreground,
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            ),
          );
          const padding = EdgeInsets.symmetric(horizontal: 14);
          return AppChip(
            label: label,
            onTap: select,
            selected: active,
            kind: AppChipKind.choice,
            cornerRadius: 10,
            fillSelected: true,
            padding: padding,
          );
        },
      ),
    );
  }
}

class _IdleBody extends StatelessWidget {
  const _IdleBody({
    required this.history,
    required this.onSelectHistory,
    required this.onClearHistory,
    required this.onRemoveHistory,
    required this.onSelectHot,
  });

  final List<String> history;
  final ValueChanged<String> onSelectHistory;
  final VoidCallback onClearHistory;
  final ValueChanged<String> onRemoveHistory;
  final ValueChanged<String> onSelectHot;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
      children: <Widget>[
        HistoryChips(
          history: history,
          onSelect: onSelectHistory,
          onClear: onClearHistory,
          onRemove: onRemoveHistory,
        ),
        if (history.isNotEmpty) const SizedBox(height: 18),
        Text(
          '热门搜索',
          style: AppTypography.bodyStrong.copyWith(color: scheme.onSurface),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: kHotKeywords.map((keyword) {
            void select() => onSelectHot(keyword);
            return AppChip(
              label: Text(keyword, style: AppTypography.caption),
              onTap: select,
              kind: AppChipKind.action,
              cornerRadius: 10,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            );
          }).toList(growable: false),
        ),
        const SizedBox(height: 22),
        Row(
          children: <Widget>[
            IconTheme(
              data: IconThemeData(color: scheme.onSurfaceVariant),
              child: const SvgIcon(AppIcons.bookOpen, size: 16),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '输入纯车号会直接进详情页；输入关键词会走服务端搜索。',
                style: AppTypography.micro
                    .copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
