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
  const SearchPage({super.key});

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  String _liveHint = '输入车号或关键词';

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    final decision = resolveQuery(value);
    setState(() => _liveHint = decision.hint);
  }

  void _submit(String value) {
    final decision = resolveQuery(value);
    if (decision.isEmpty) return;
    if (decision.isAlbum) {
      _focusNode.unfocus();
      context.push('/album/${decision.albumId}');
      return;
    }
    _focusNode.unfocus();
    ref.read(searchControllerProvider.notifier).search(decision.keyword!);
  }

  void _fillHistory(String keyword) {
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
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: SearchField(
                controller: _controller,
                focusNode: _focusNode,
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
            Expanded(
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
                      _SortBar(
                        selected: results.order,
                        onSelected: (order) => ref
                            .read(searchControllerProvider.notifier)
                            .setSort(order),
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
                          onTap: (album) => context.push('/album/${album.id}'),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
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
      height: 40,
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
              active ? scheme.onPrimaryContainer : scheme.onSurfaceVariant;
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
            foregroundColor: foreground,
            onTap: select,
            selected: active,
            kind: AppChipKind.choice,
            padding: padding,
            metalChild: GestureDetector(
              onTap: select,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding: padding,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: active ? scheme.primaryContainer : Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: active ? Colors.transparent : scheme.outlineVariant,
                  ),
                ),
                child: label,
              ),
            ),
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
              metalChild: ActionChip(
                label: Text(keyword),
                onPressed: select,
                labelStyle:
                    AppTypography.caption.copyWith(color: scheme.onSurface),
                backgroundColor: scheme.surfaceContainer,
                side: BorderSide(color: scheme.outlineVariant),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
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
