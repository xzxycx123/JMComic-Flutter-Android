import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/icons/app_icons.dart';
import '../../core/theme/app_typography.dart';
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

    return Scaffold(
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
                  style: AppTypography.micro.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
            ),
            Expanded(
              child: resultState.when(
                loading: () => const Center(
                  child: SizedBox(
                    width: 26,
                    height: 26,
                    child: CircularProgressIndicator(strokeWidth: 2.4),
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
                      onSelectHot: _fillHistory,
                    );
                  }
                  if (results.isEmpty) {
                    return EmptyState(
                      illustration: AppIllustrations.emptySearch,
                      title: '没有找到相关本子',
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
                      ResultHeader(total: results.total, keyword: results.keyword),
                      Expanded(
                        child: ResultGrid(
                          items: results.items,
                          loadingMore: results.loadingMore,
                          error: results.error,
                          onRetry: () =>
                              ref.read(searchControllerProvider.notifier).loadMore(),
                          onLoadMore: () =>
                              ref.read(searchControllerProvider.notifier).loadMore(),
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

class _IdleBody extends StatelessWidget {
  const _IdleBody({
    required this.history,
    required this.onSelectHistory,
    required this.onClearHistory,
    required this.onSelectHot,
  });

  final List<String> history;
  final ValueChanged<String> onSelectHistory;
  final VoidCallback onClearHistory;
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
        ),
        if (history.isNotEmpty) const SizedBox(height: 18),
        Text('热门搜索', style: AppTypography.bodyStrong.copyWith(color: scheme.onSurface)),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: kHotKeywords.map((keyword) {
            return ActionChip(
              label: Text(keyword),
              onPressed: () => onSelectHot(keyword),
              labelStyle: AppTypography.caption.copyWith(color: scheme.onSurface),
              backgroundColor: scheme.surfaceContainer,
              side: BorderSide(color: scheme.outlineVariant),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
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
                style: AppTypography.micro.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
