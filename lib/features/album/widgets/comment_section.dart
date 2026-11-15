import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/di/providers.dart';
import '../../../core/icons/app_icons.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../data/models/jm_comment.dart';
import '../../../data/sources/jm_api_client.dart';
import '../../collect/collect_providers.dart';
import '../../home/widgets/section_header.dart';
import '../album_providers.dart';

/// 详情页评论区：列表（先铺 5 条，按需展开）+「写评论」入口。
///
/// 接口：`GET /forum?page&aid&mode=manhua`（未登录可读）。
class CommentSection extends ConsumerStatefulWidget {
  const CommentSection({required this.albumId, super.key, this.totalHint = 0});

  final String albumId;
  final int totalHint;

  @override
  ConsumerState<CommentSection> createState() => _CommentSectionState();
}

class _CommentSectionState extends ConsumerState<CommentSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final async = ref.watch(albumCommentsProvider(widget.albumId));
    final state = async.valueOrNull;
    final total = (state?.total ?? 0) > 0 ? state!.total : widget.totalHint;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SectionHeader(title: total > 0 ? '评论 $total' : '评论'),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: _ComposerEntry(
            albumId: widget.albumId,
            onDone: () => setState(() => _expanded = true),
          ),
        ),
        if (async.isLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2.2),
              ),
            ),
          )
        else if (async.hasError)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              children: <Widget>[
                IconTheme(
                  data: IconThemeData(color: scheme.onSurfaceVariant),
                  child: const SvgIcon(AppIcons.alert, size: 16),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '评论加载失败：${async.error}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.caption
                        .copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
                TextButton(
                  onPressed: () => ref
                      .read(albumCommentsProvider(widget.albumId).notifier)
                      .refresh(),
                  child: const Text('重试'),
                ),
              ],
            ),
          )
        else if (state == null || state.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: Text(
              '还没有评论，来说两句',
              style: AppTypography.caption.copyWith(color: scheme.onSurfaceVariant),
            ),
          )
        else ...<Widget>[
          ...() {
            final items = _expanded ? state.items : state.preview;
            final api = ref.watch(jmApiProvider);
            return items.map(
              (comment) => CommentTile(
                comment: comment,
                resolveAvatar: (path) => _resolveAvatar(api, path),
                imageHeaders: api.imageHeaders,
                onReply: () => _openComposer(context, ref, parentId: comment.id),
              ),
            );
          }(),
          if (!_expanded && state.items.length > 5)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
              child: OutlinedButton(
                onPressed: () => setState(() => _expanded = true),
                child: Text('查看全部 ${state.total > 0 ? state.total : state.items.length} 条评论'),
              ),
            ),
          if (_expanded && state.hasMore)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
              child: OutlinedButton(
                onPressed: state.loadingMore
                    ? null
                    : () => ref
                        .read(albumCommentsProvider(widget.albumId).notifier)
                        .loadMore(),
                child: state.loadingMore
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('加载更多评论'),
              ),
            ),
        ],
        if (state != null && state.error != null && !async.hasError)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              state.error!,
              style: AppTypography.micro.copyWith(color: scheme.error),
            ),
          ),
      ],
    );
  }

  Future<void> _openComposer(
    BuildContext context,
    WidgetRef ref, {
    String? parentId,
  }) async {
    if (!_isLoggedIn(ref)) {
      await askForLogin(context);
      return;
    }
    final draft = await showCommentComposer(
      context,
      albumId: widget.albumId,
      parentId: parentId,
    );
    if (draft == null || !context.mounted) return;
    setState(() => _expanded = true);
    sendCommentOptimistically(
      context,
      ref,
      albumId: widget.albumId,
      draft: draft,
      parentId: parentId,
    );
  }

  static bool _isLoggedIn(WidgetRef ref) =>
      ref.read(accountSessionProvider).valueOrNull?.isLoggedIn ?? false;

  static String _resolveAvatar(JmApi api, String path) {
    final value = path.trim();
    if (value.isEmpty) return '';
    if (value.startsWith('http')) return value;
    final host = api.imageHost.replaceFirst(RegExp(r'^https?://'), '');
    if (host.isEmpty) return '';
    return 'https://$host${value.startsWith('/') ? '' : '/'}$value';
  }
}

/// 前台先给「已发送」，网络请求在后台跑；失败再弹错误并把那条撤回。
void sendCommentOptimistically(
  BuildContext context,
  WidgetRef ref, {
  required String albumId,
  required CommentDraft draft,
  String? parentId,
}) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.showSnackBar(const SnackBar(content: Text('评论已发送')));
  unawaited(
    ref
        .read(albumCommentsProvider(albumId).notifier)
        .post(draft.content, spoiler: draft.spoiler, parentId: parentId)
        .catchError((Object error) {
      messenger.showSnackBar(SnackBar(content: Text('发送失败：$error')));
      return '';
    }),
  );
}

/// 登录门槛：没登录就弹「去登录」，不静默失败。
Future<void> askForLogin(BuildContext context) async {
  final go = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      icon: SvgIcon(
        AppIcons.user,
        size: 26,
        color: Theme.of(context).colorScheme.primary,
      ),
      title: const Text('登录后才能操作'),
      content: const Text('点赞和评论都挂在账号上。登录只保存会话 cookie，不保存密码。'),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('先不登录'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('去登录'),
        ),
      ],
    ),
  );
  if (go == true && context.mounted) unawaited(context.push('/login'));
}

/// 「说点什么…」入口条。
class _ComposerEntry extends ConsumerWidget {
  const _ComposerEntry({required this.albumId, required this.onDone});

  final String albumId;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainer,
      borderRadius: BorderRadius.circular(AppColors.radiusPill),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppColors.radiusPill),
        onTap: () async {
          if (!(ref.read(accountSessionProvider).valueOrNull?.isLoggedIn ?? false)) {
            await askForLogin(context);
            return;
          }
          final draft = await showCommentComposer(context, albumId: albumId);
          if (draft == null || !context.mounted) return;
          onDone();
          sendCommentOptimistically(
            context,
            ref,
            albumId: albumId,
            draft: draft,
          );
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          child: Row(
            children: <Widget>[
              IconTheme(
                data: IconThemeData(color: scheme.onSurfaceVariant),
                child: const SvgIcon(AppIcons.comment, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '说点什么…',
                  style: AppTypography.caption
                      .copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
              IconTheme(
                data: IconThemeData(color: scheme.primary),
                child: const SvgIcon(AppIcons.send, size: 18),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 单条评论。
class CommentTile extends StatelessWidget {
  const CommentTile({
    required this.comment,
    required this.resolveAvatar,
    required this.imageHeaders,
    super.key,
    this.onReply,
    this.isReply = false,
  });

  final JmComment comment;
  final String Function(String path) resolveAvatar;
  final Map<String, String> imageHeaders;
  final VoidCallback? onReply;
  final bool isReply;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(isReply ? 52 : 16, 6, 16, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _Avatar(
            url: resolveAvatar(comment.avatar),
            headers: imageHeaders,
            initial: comment.initial,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Flexible(
                      child: Text(
                        comment.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.caption.copyWith(
                          color: scheme.onSurface,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (comment.spoiler) ...<Widget>[
                      const SizedBox(width: 6),
                      _Tag(text: '剧透', color: scheme.error),
                    ],
                    if (comment.pending) ...<Widget>[
                      const SizedBox(width: 6),
                      _Tag(text: '发送中', color: scheme.onSurfaceVariant),
                    ],
                    const SizedBox(width: 6),
                    Text(
                      comment.displayTime,
                      style: AppTypography.micro
                          .copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  comment.content,
                  style: AppTypography.body.copyWith(color: scheme.onSurface),
                ),
                const SizedBox(height: 4),
                Row(
                  children: <Widget>[
                    IconTheme(
                      data: IconThemeData(color: scheme.onSurfaceVariant),
                      child: const SvgIcon(AppIcons.heart, size: 13),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${comment.likes}',
                      style: AppTypography.micro
                          .copyWith(color: scheme.onSurfaceVariant),
                    ),
                    if (onReply != null) ...<Widget>[
                      const SizedBox(width: 12),
                      InkWell(
                        onTap: onReply,
                        child: Text(
                          '回复',
                          style: AppTypography.micro.copyWith(color: scheme.primary),
                        ),
                      ),
                    ],
                  ],
                ),
                for (final reply in comment.replies.take(3))
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: CommentTile(
                      comment: reply,
                      resolveAvatar: resolveAvatar,
                      imageHeaders: imageHeaders,
                      isReply: true,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.url, required this.headers, required this.initial});

  final String url;
  final Map<String, String> headers;
  final String initial;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fallback = Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(AppColors.radiusPill),
      ),
      child: Text(
        initial,
        style: AppTypography.caption.copyWith(
          color: scheme.onPrimaryContainer,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
    if (url.isEmpty) return fallback;
    return ClipOval(
      child: CachedNetworkImage(
        imageUrl: url,
        httpHeaders: headers,
        width: 32,
        height: 32,
        fit: BoxFit.cover,
        placeholder: (context, value) => fallback,
        errorWidget: (context, value, error) => fallback,
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text, style: AppTypography.micro.copyWith(color: color)),
    );
  }
}

/// 写评论面板的返回值：面板一关就把草稿交给调用方，网络请求在后台跑。
class CommentDraft {
  const CommentDraft(this.content, {this.spoiler = false});

  final String content;
  final bool spoiler;
}

/// 打开写评论面板；填好后立即返回草稿（不阻塞在网络请求上），取消返回 null。
Future<CommentDraft?> showCommentComposer(
  BuildContext context, {
  required String albumId,
  String? parentId,
}) {
  return showModalBottomSheet<CommentDraft>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => _ComposerSheet(
      albumId: albumId,
      parentId: parentId,
    ),
  );
}

class _ComposerSheet extends ConsumerStatefulWidget {
  const _ComposerSheet({required this.albumId, this.parentId});

  final String albumId;
  final String? parentId;

  @override
  ConsumerState<_ComposerSheet> createState() => _ComposerSheetState();
}

class _ComposerSheetState extends ConsumerState<_ComposerSheet> {
  final TextEditingController _controller = TextEditingController();
  bool _spoiler = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onChanged() => setState(() {});

  /// 立刻关闭面板并把草稿带出去：发送在列表侧后台进行，用户不用等转圈。
  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    Navigator.of(context).pop(CommentDraft(text, spoiler: _spoiler));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 4,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            widget.parentId == null ? '写评论' : '回复评论',
            style: AppTypography.sectionTitle.copyWith(color: scheme.onSurface),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _controller,
            autofocus: true,
            maxLines: 4,
            minLines: 3,
            maxLength: 500,
            textInputAction: TextInputAction.newline,
            decoration: const InputDecoration(hintText: '友善发言，剧透请勾选下方选项'),
          ),
          Row(
            children: <Widget>[
              Expanded(
                child: Row(
                  children: <Widget>[
                    Switch.adaptive(
                      value: _spoiler,
                      onChanged: (value) => setState(() => _spoiler = value),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '含剧透',
                      style: AppTypography.caption
                          .copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('取消'),
              ),
              const SizedBox(width: 6),
              FilledButton(
                onPressed: _controller.text.trim().isEmpty ? null : _submit,
                child: const Text('发送'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
