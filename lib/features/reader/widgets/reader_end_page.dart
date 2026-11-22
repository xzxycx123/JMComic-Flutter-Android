import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/icons/app_icons.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/ui/app_toast.dart';
import '../../../core/ui/glass/app_glass.dart';
import '../../../data/models/jm_album_summary.dart';
import '../../album/album_providers.dart';
import '../../album/widgets/comment_section.dart' show askForLogin;
import '../../collect/collect_providers.dart';

/// 当前阅读单元（章节）能不能走既有下载管线。
///
/// 「作品支持下载」的判定标准：有可读页面，且专辑 / 章节 id 都在。
/// 两者缺一都没法定位到图片，按钮置灰并在页面上写明原因。
bool canDownloadReaderUnit({
  required String albumId,
  required String chapterId,
  required int total,
}) =>
    total > 0 && albumId.isNotEmpty && chapterId.isNotEmpty;

/// 阅读器结束页：读完当前可阅读单元后挂在末尾。
///
/// 只做「收尾三件事」：下载（复用阅读缓存、缺页补齐）、收藏、点赞。
/// 收藏 / 点赞直接复用详情页的 provider，不另造一套状态。
class ReaderEndPage extends ConsumerStatefulWidget {
  const ReaderEndPage({
    required this.albumId,
    required this.chapterId,
    required this.albumTitle,
    required this.chapterTitle,
    required this.total,
    required this.cachedPages,
    required this.onDownload,
    super.key,
    this.onTap,
    this.busyDownload = false,
    this.embeddedExtent,
  });

  final String albumId;
  final String chapterId;
  final String albumTitle;
  final String chapterTitle;

  /// 当前单元总页数（不是「页码」：结束页自己不计入总数）。
  final int total;

  /// 进入结束页时阅读器缓存里已命中的页数（只用于文案）。
  final int cachedPages;

  /// 下载回调：由阅读器负责把缓存闭包交给下载引擎。
  final Future<void> Function() onDownload;

  /// 点空白处（不落在按钮上）切换 HUD。
  final VoidCallback? onTap;

  /// 下载请求处理中（按钮显示 loading，避免重复点击的无声等待）。
  final bool busyDownload;

  /// 竖读模式下的固定高度；非空时结束页不再用内部滚动视图（不抢外层回滚手势）。
  final double? embeddedExtent;

  @override
  ConsumerState<ReaderEndPage> createState() => _ReaderEndPageState();
}

class _ReaderEndPageState extends ConsumerState<ReaderEndPage> {
  bool _favoriteBusy = false;
  bool _likeBusy = false;

  @override
  void initState() {
    super.initState();
    // 到结束页才补一次详情：点赞数 / 已赞状态、收藏条目的作者都来自它。
    // 从详情页点进来的话这里直接命中 provider 缓存，不会重复请求。
    WidgetsBinding.instance.addPostFrameCallback((_) => _primeAlbumDetail());
  }

  Future<void> _primeAlbumDetail() async {
    try {
      await ref.read(albumDetailProvider(widget.albumId).future);
    } catch (_) {
      // 详情拉不到不影响结束页：收藏走本地账本，点赞按未知态起步。
      return;
    }
    if (!mounted) return;
    // 详情晚到：把点赞状态从详情同步回来（已经点过的情况）。
    if (!ref.read(albumLikeProvider(widget.albumId)).liked) {
      ref.invalidate(albumLikeProvider(widget.albumId));
    }
  }

  JmAlbumSummary _favoriteSummary() {
    final detail = ref.read(albumDetailProvider(widget.albumId)).valueOrNull;
    final existing = ref
        .read(favoritesItemsProvider)
        .firstWhereOrNull((item) => item.albumId == widget.albumId);
    return JmAlbumSummary(
      id: widget.albumId,
      // 专辑标题未知时留空（展示端回落 JM 号），不拿章节名冒充专辑名。
      title: detail?.title ?? widget.albumTitle,
      // 详情没拉到、本地已有条目时保留原作者，避免把账本信息洗成 N/A。
      author: detail?.authorName ?? existing?.author ?? 'N/A',
    );
  }

  Future<void> _toggleFavorite() async {
    if (_favoriteBusy) return;
    final repository = ref.read(favoritesRepositoryProvider);
    final summary = _favoriteSummary();
    setState(() => _favoriteBusy = true);
    try {
      final added = await repository.toggle(summary);
      ref.read(favoritesItemsProvider.notifier).reload();
      if (!mounted) return;
      AppToast.show(
        context,
        added ? '已收藏' : '已取消收藏',
        actionLabel: '撤销',
        onAction: () {
          unawaited(() async {
            await repository.undo(added, summary);
            ref.read(favoritesItemsProvider.notifier).reload();
          }());
        },
      );
    } catch (error) {
      if (mounted) AppToast.show(context, '收藏失败：$error');
    } finally {
      if (mounted) setState(() => _favoriteBusy = false);
    }
  }

  /// 登录态：会话还在恢复时等它一次，别把「还没恢复完」当成「没登录」。
  Future<bool> _isLoggedIn() async {
    final current = ref.read(accountSessionProvider).valueOrNull;
    if (current != null) return current.isLoggedIn;
    try {
      final session = await ref.read(accountSessionProvider.future);
      return session.isLoggedIn;
    } catch (_) {
      return false;
    }
  }

  Future<void> _like() async {
    if (_likeBusy) return;
    final state = ref.read(albumLikeProvider(widget.albumId));
    if (state.liked) {
      AppToast.show(context, '这本已经点过赞了');
      return;
    }
    if (!await _isLoggedIn()) {
      if (!mounted) return;
      await askForLogin(context);
      return;
    }
    if (!mounted) return;
    setState(() => _likeBusy = true);
    // 与详情页一致：先亮成功，网络在后台跑，失败再回滚并提示。
    final pending = ref.read(albumLikeProvider(widget.albumId).notifier).like();
    AppToast.show(context, '已点赞');
    final ok = await pending;
    if (!mounted) return;
    setState(() => _likeBusy = false);
    // 已点过 / 正在发送时 like() 也会返回 false，只有真的带错误才算失败。
    if (ok) return;
    final error = ref.read(albumLikeProvider(widget.albumId)).error;
    if (error != null) AppToast.show(context, '点赞失败：$error');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final favorite = ref.watch(favoriteIdsProvider).contains(widget.albumId);
    final like = ref.watch(albumLikeProvider(widget.albumId));
    final downloadEnabled = canDownloadReaderUnit(
      albumId: widget.albumId,
      chapterId: widget.chapterId,
      total: widget.total,
    );
    final likeLabel = like.liked
        ? (like.likes > 0 ? '已点赞 ${like.likes}' : '已点赞')
        : (like.likes > 0 ? '点赞 ${like.likes}' : '点赞');

    return _EndPageLayout(
      total: widget.total,
      cachedPages: widget.cachedPages,
      downloadEnabled: downloadEnabled,
      downloadLabel: '下载',
      favoriteLabel: favorite ? '已收藏' : '收藏',
      favoriteSelected: favorite,
      likeLabel: likeLabel,
      likeSelected: like.liked,
      favoriteBusy: _favoriteBusy,
      likeBusy: _likeBusy,
      downloadBusy: widget.busyDownload,
      onDownload: downloadEnabled ? () => unawaited(widget.onDownload()) : null,
      onToggleFavorite:
          _favoriteBusy ? null : () => unawaited(_toggleFavorite()),
      onLike: _likeBusy ? null : () => unawaited(_like()),
      onTap: widget.onTap,
      embeddedExtent: widget.embeddedExtent,
      accent: scheme.primary,
    );
  }
}

class _EndPageLayout extends StatelessWidget {
  const _EndPageLayout({
    required this.total,
    required this.cachedPages,
    required this.downloadEnabled,
    required this.downloadLabel,
    required this.favoriteLabel,
    required this.favoriteSelected,
    required this.likeLabel,
    required this.likeSelected,
    required this.favoriteBusy,
    required this.likeBusy,
    required this.downloadBusy,
    required this.onDownload,
    required this.onToggleFavorite,
    required this.onLike,
    required this.accent,
    this.onTap,
    this.embeddedExtent,
  });

  final int total;
  final int cachedPages;
  final bool downloadEnabled;
  final String downloadLabel;
  final String favoriteLabel;
  final bool favoriteSelected;
  final String likeLabel;
  final bool likeSelected;
  final bool favoriteBusy;
  final bool likeBusy;
  final bool downloadBusy;
  final VoidCallback? onDownload;
  final VoidCallback? onToggleFavorite;
  final VoidCallback? onLike;
  final VoidCallback? onTap;
  final double? embeddedExtent;
  final Color accent;

  String get _hint {
    if (!downloadEnabled) return '这本缺少可导出的页面信息，暂时无法下载';
    if (cachedPages > 0) return '下载会复用已有 $cachedPages/$total 页缓存，缺页自动补齐';
    return '下载会按页序补齐 $total 页后合并成一个 PDF';
  }

  @override
  Widget build(BuildContext context) {
    const ink = AppColors.readerInk;
    final embedded = embeddedExtent != null;
    Widget content = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SafeArea(
        top: false,
        child: Center(
          child: SingleChildScrollView(
            // 竖读时结束页嵌在外层列表里：自身不滚动，纵向回滚手势交给外层列表。
            physics: embedded ? const NeverScrollableScrollPhysics() : null,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 260, maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Semantics(
                    header: true,
                    child: Text(
                      '（全书完）',
                      textAlign: TextAlign.center,
                      style: AppTypography.title.copyWith(
                        color: ink,
                        letterSpacing: 2,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '已读到最后一页 · 共 $total 页',
                    textAlign: TextAlign.center,
                    style: AppTypography.caption.copyWith(
                      color: ink.withValues(alpha: 0.65),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _hint,
                    textAlign: TextAlign.center,
                    style: AppTypography.micro.copyWith(
                      color: ink.withValues(alpha: 0.45),
                    ),
                  ),
                  const SizedBox(height: 22),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 10,
                    runSpacing: 10,
                    children: <Widget>[
                      AppButton(
                        onPressed: onDownload,
                        loading: downloadBusy,
                        label: downloadLabel,
                        height: 44,
                        cornerRadius: AppColors.radiusPill,
                        leadingIcon: const SvgIcon(AppIcons.download, size: 18),
                      ),
                      Semantics(
                        toggled: favoriteSelected,
                        child: AppButton.secondary(
                          onPressed: onToggleFavorite,
                          loading: favoriteBusy,
                          label: favoriteLabel,
                          height: 44,
                          cornerRadius: AppColors.radiusPill,
                          foregroundColor:
                              favoriteSelected ? accent : AppColors.readerInk,
                          leadingIcon: SvgIcon(
                            favoriteSelected
                                ? AppIcons.starFilled
                                : AppIcons.star,
                            size: 18,
                          ),
                        ),
                      ),
                      Semantics(
                        toggled: likeSelected,
                        child: AppButton.secondary(
                          onPressed: onLike,
                          loading: likeBusy,
                          label: likeLabel,
                          height: 44,
                          cornerRadius: AppColors.radiusPill,
                          foregroundColor:
                              likeSelected ? accent : AppColors.readerInk,
                          leadingIcon: SvgIcon(
                            likeSelected
                                ? AppIcons.heartFilled
                                : AppIcons.heart,
                            size: 18,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (embedded) {
      // 固定高度 = 阅读器算页码时扣掉的 footerExtent，两者必须一致。
      content = SizedBox(height: embeddedExtent, child: content);
    }
    return content;
  }
}
