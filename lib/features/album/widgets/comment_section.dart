import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/di/providers.dart';
import '../../../core/icons/app_icons.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/ui/app_toast.dart';
import '../../../core/ui/glass/app_glass.dart';
import '../../../data/models/jm_comment.dart';
import '../../../data/sources/jm_api_client.dart';
import '../../collect/collect_providers.dart';
import '../../home/widgets/section_header.dart';
import '../album_providers.dart';
import '../comment_filter.dart';

/// 详情页评论区：列表（先铺 5 条，按需展开）+「写评论」入口。
///
/// 接口：`GET /forum?page&aid&mode=manhua`（未登录可读）。
///
/// 默认隐藏「emoji 数量 > [kAdEmojiThreshold]」的条目（顶层与 replies 都过滤），
/// 只有用户展开评论、并滑到评论列表底部后，才给一个找回入口。
class CommentSection extends ConsumerStatefulWidget {
  const CommentSection({
    required this.albumId,
    super.key,
    this.totalHint = 0,
    this.bottomReached = false,
  });

  final String albumId;
  final int totalHint;

  /// 外层 `CustomScrollView` 是否已经滑到列表底部（由详情页滚动通知驱动）。
  final bool bottomReached;

  @override
  ConsumerState<CommentSection> createState() => _CommentSectionState();
}

class _CommentSectionState extends ConsumerState<CommentSection> {
  bool _expanded = false;

  /// 用户是否点了「显示可能存在广告的评论」。
  bool _showHidden = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final async = ref.watch(albumCommentsProvider(widget.albumId));
    final state = async.valueOrNull;
    final total = (state?.total ?? 0) > 0 ? state!.total : widget.totalHint;
    // 过滤只作用于展示：服务端列表与 total 原样保留。
    final allItems = state?.items ?? const <JmComment>[];
    final filter = CommentFilter(showHidden: _showHidden);
    final hiddenCount = filter.hiddenCount(allItems);
    final showHiddenButton =
        _expanded && widget.bottomReached && hiddenCount > 0;

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
                child: AppProgressIndicator.circular(strokeWidth: 2.2),
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
                AppButton.text(
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
              style: AppTypography.caption
                  .copyWith(color: scheme.onSurfaceVariant),
            ),
          )
        else ...<Widget>[
          ...() {
            final source = _expanded ? allItems : state.preview;
            final items = filter.apply(source);
            final api = ref.watch(jmApiProvider);
            return items.map(
              (comment) => CommentTile(
                comment: comment,
                filter: filter,
                resolveAvatar: (path) => _resolveAvatar(api, path),
                imageHeaders: api.imageHeaders,
                onReply: () =>
                    _openComposer(context, ref, parentId: comment.id),
              ),
            );
          }(),
          if (!_expanded && state.items.length > 5)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
              child: AppButton.secondary(
                cornerRadius: AppColors.radiusPill,
                onPressed: () => setState(() => _expanded = true),
                child: Text(
                  '查看全部 ${state.total > 0 ? state.total : state.items.length} 条评论',
                ),
              ),
            ),
          if (_expanded && state.hasMore)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
              child: AppButton.secondary(
                cornerRadius: AppColors.radiusPill,
                onPressed: () => ref
                    .read(albumCommentsProvider(widget.albumId).notifier)
                    .loadMore(),
                loading: state.loadingMore,
                label: '加载更多评论',
              ),
            ),
          if (showHiddenButton)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
              child: AppButton.secondary(
                cornerRadius: AppColors.radiusPill,
                height: 40,
                semanticLabel: _showHidden
                    ? '隐藏可能存在广告的评论（$hiddenCount 条）'
                    : '显示可能存在广告的评论（$hiddenCount 条）',
                onPressed: () => setState(() => _showHidden = !_showHidden),
                leadingIcon: SvgIcon(
                  _showHidden ? AppIcons.eyeOff : AppIcons.eye,
                  size: 16,
                  color: scheme.onSurface,
                ),
                label: _showHidden ? '隐藏可能存在广告的评论' : '显示可能存在广告的评论',
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
  AppToast.show(context, '评论已发送');
  unawaited(
    ref
        .read(albumCommentsProvider(albumId).notifier)
        .post(draft.content, spoiler: draft.spoiler, parentId: parentId)
        .catchError((Object error) {
      if (context.mounted) AppToast.show(context, '发送失败：$error');
      return '';
    }),
  );
}

/// 登录门槛：没登录就弹「去登录」，不静默失败。
Future<void> askForLogin(BuildContext context) async {
  final go = await AppDialog.show<bool>(
    context: context,
    iconBuilder: (context) => SvgIcon(
      AppIcons.user,
      size: 26,
      color: Theme.of(context).colorScheme.primary,
    ),
    title: '登录后才能操作',
    message: '点赞和评论都挂在账号上。登录只保存会话 cookie，不保存密码。',
    actions: const <AppDialogAction<bool>>[
      AppDialogAction(label: '先不登录', result: false),
      AppDialogAction(label: '去登录', result: true, primary: true),
    ],
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
    Future<void> open() async {
      if (!(ref.read(accountSessionProvider).valueOrNull?.isLoggedIn ??
          false)) {
        await askForLogin(context);
        return;
      }
      final draft = await showCommentComposer(context, albumId: albumId);
      if (draft == null || !context.mounted) return;
      onDone();
      sendCommentOptimistically(context, ref, albumId: albumId, draft: draft);
    }

    final radius = BorderRadius.circular(AppColors.radiusPill);
    const padding = EdgeInsets.symmetric(horizontal: 16, vertical: 11);
    final content = Row(
      children: <Widget>[
        SvgIcon(AppIcons.comment, size: 18, color: scheme.onSurfaceVariant),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            '说点什么…',
            style:
                AppTypography.caption.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
        SvgIcon(AppIcons.send, size: 18, color: scheme.primary),
      ],
    );
    return AppSurface(
      kind: AppSurfaceKind.controlGroup,
      borderRadius: radius,
      onTap: open,
      padding: padding,
      metalDecoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: radius,
      ),
      child: content,
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
    this.filter = const CommentFilter(),
  });

  final JmComment comment;
  final String Function(String path) resolveAvatar;
  final Map<String, String> imageHeaders;
  final VoidCallback? onReply;
  final bool isReply;

  /// 回复列表同样按 emoji 规则过滤（这里只影响展示，不改原始对象）。
  final CommentFilter filter;

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
                    // 注意：`/forum` 的 `spoiler` 字段实测恒为 "1"（不是剧透标记，
                    // 更像「已处理过剧透内容」的服务端状态位），所以这里不再按它打标签，
                    // 否则每条评论都会挂一个「剧透」。
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
                // 评论点赞已下线：`/forum.likes` 对游客恒为 "0"，站点自己的评论点赞入口
                // 也已注释停用（见研究结论），所以这里不再渲染爱心/计数。
                if (onReply != null) ...<Widget>[
                  const SizedBox(height: 4),
                  if (context.isLiquidGlass)
                    AppButton.text(
                      onPressed: onReply,
                      foregroundColor: scheme.primary,
                      child: const Text('回复', style: AppTypography.micro),
                    )
                  else
                    InkWell(
                      onTap: onReply,
                      child: Text(
                        '回复',
                        style:
                            AppTypography.micro.copyWith(color: scheme.primary),
                      ),
                    ),
                ],
                for (final reply in filter.repliesOf(comment).take(3))
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: CommentTile(
                      comment: reply,
                      resolveAvatar: resolveAvatar,
                      imageHeaders: imageHeaders,
                      isReply: true,
                      filter: filter,
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
  const _Avatar({
    required this.url,
    required this.headers,
    required this.initial,
  });

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
    final label = Text(text, style: AppTypography.micro.copyWith(color: color));
    return AppBadge(
      label: label,
      metalChild: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(4),
        ),
        child: label,
      ),
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
///
/// 面板不走 `GlassModalSheet` 的定高抽屉：那是「整屏 x 92%」的尺寸，键盘弹出后
/// 会剩一大片空玻璃。这里用透明的 modal sheet 承载一块**内容高度**的浮层，
/// 键盘高度作为 sheet 内的透明底部 padding，于是抽屉始终紧贴输入法上沿。
Future<CommentDraft?> showCommentComposer(
  BuildContext context, {
  required String albumId,
  String? parentId,
}) {
  return showModalBottomSheet<CommentDraft>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: .32),
    elevation: 0,
    clipBehavior: Clip.none,
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
  /// 与 `/forum` 的正文上限一致；计数改到标题行右侧，不再额外占一行高度。
  static const int _maxLength = 500;

  final TextEditingController _controller = TextEditingController();
  bool _spoiler = false;
  bool _closing = false;

  void _close([CommentDraft? draft]) {
    if (_closing || ModalRoute.of(context)?.isCurrent != true) return;
    _closing = true;
    Navigator.of(context).pop(draft);
  }

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
    _close(CommentDraft(text, spoiler: _spoiler));
  }

  /// 固定高度的输入井：约 3 行正文，大字号时按文字缩放入参，最矮 90、
  /// 最高 200 —— 不再随 minLines 越撑越高，也不给文字下方留一片空井。
  double _fieldHeight(BuildContext context) {
    final line = MediaQuery.textScalerOf(context).scale(
      AppTypography.body.fontSize! * (AppTypography.body.height ?? 1.4),
    );
    return (line * 3 + 30).clamp(90.0, 200.0);
  }

  /// 输入框内边距：文字离上边留 16，离下边 14 —— 第一行不再贴边框。
  static const EdgeInsets _fieldInset = EdgeInsets.fromLTRB(16, 16, 16, 14);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // 键盘高度只作为 sheet 内的透明底部留白，面板本身永远等于内容高度：
    // 抽屉上沿始终贴着输入法上沿，键盘收起时再落回屏幕底部。
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final text = _controller.text;
    final canSend = text.trim().isNotEmpty;
    final radius = BorderRadius.circular(26);
    return AnimatedPadding(
      duration:
          reduceMotion ? Duration.zero : const Duration(milliseconds: 160),
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.only(bottom: keyboard),
      child: SafeArea(
        top: false,
        bottom: keyboard == 0,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          child: AppSurface(
            kind: AppSurfaceKind.overlay,
            borderRadius: radius,
            metalDecoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: radius,
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: scheme.shadow.withValues(alpha: .10),
                  blurRadius: 28,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * .62,
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: scheme.onSurfaceVariant.withValues(alpha: .35),
                          borderRadius:
                              BorderRadius.circular(AppColors.radiusPill),
                        ),
                      ),
                    ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            widget.parentId == null ? '写评论' : '回复评论',
                            style: AppTypography.sectionTitle
                                .copyWith(color: scheme.onSurface),
                          ),
                        ),
                        Text(
                          '${text.length}/$_maxLength',
                          style: AppTypography.micro
                              .copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: _fieldHeight(context),
                      child: Stack(
                        children: <Widget>[
                          Positioned.fill(
                            child: AppTextField(
                              controller: _controller,
                              autofocus: true,
                              expands: true,
                              maxLines: null,
                              minLines: null,
                              // 圆角矩形 + 连续曲率：Metal 与 LiquidGlass 同形，
                              // 只是一个实色井、一个玻璃井。
                              cornerRadius: 16,
                              contentPadding: _fieldInset,
                              textAlignVertical: TextAlignVertical.top,
                              textInputAction: TextInputAction.newline,
                              style: AppTypography.body
                                  .copyWith(color: scheme.onSurface),
                              inputFormatters: <TextInputFormatter>[
                                LengthLimitingTextInputFormatter(_maxLength),
                              ],
                              decoration: const InputDecoration(),
                            ),
                          ),
                          // 占位文案自己画在左上角（与 contentPadding 对齐），避免
                          // InputDecorator 在多行 + expands 时把 hint 摆到垂直居中。
                          if (text.isEmpty)
                            Positioned(
                              left: _fieldInset.left,
                              top: _fieldInset.top,
                              right: _fieldInset.right,
                              child: IgnorePointer(
                                child: Text(
                                  '友善发言，剧透请勾选下方选项',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTypography.body
                                      .copyWith(color: scheme.onSurfaceVariant),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: <Widget>[
                        AppSwitch.adaptive(
                          value: _spoiler,
                          onChanged: (value) =>
                              setState(() => _spoiler = value),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '含剧透',
                          style: AppTypography.caption.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        const Spacer(),
                        AppButton.text(
                          onPressed: _close,
                          height: 40,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: const Text('取消'),
                        ),
                        const SizedBox(width: 4),
                        AppButton(
                          cornerRadius: AppColors.radiusPill,
                          height: 40,
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          onPressed: canSend ? _submit : null,
                          label: '发送',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
