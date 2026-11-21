import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// 全项目唯一的图标入口：只用 assets/icons/*.svg，禁止 emoji 与 Icons.*。
abstract final class AppIcons {
  static const String home = 'assets/icons/home.svg';
  static const String user = 'assets/icons/user.svg';
  static const String download = 'assets/icons/download.svg';
  static const String search = 'assets/icons/search.svg';
  static const String back = 'assets/icons/back.svg';
  static const String forward = 'assets/icons/forward.svg';
  static const String close = 'assets/icons/close.svg';
  static const String eye = 'assets/icons/eye.svg';
  static const String eyeOff = 'assets/icons/eye-off.svg';
  static const String theme = 'assets/icons/theme.svg';
  static const String bookmark = 'assets/icons/bookmark.svg';
  static const String play = 'assets/icons/play.svg';
  static const String bookOpen = 'assets/icons/book-open.svg';
  static const String grid = 'assets/icons/grid.svg';
  static const String list = 'assets/icons/list.svg';
  static const String refresh = 'assets/icons/refresh.svg';
  static const String pause = 'assets/icons/pause.svg';
  static const String trash = 'assets/icons/trash.svg';
  static const String folder = 'assets/icons/folder.svg';
  static const String share = 'assets/icons/share.svg';
  static const String settings = 'assets/icons/settings.svg';
  static const String check = 'assets/icons/check.svg';
  static const String alert = 'assets/icons/alert.svg';
  static const String scrollMode = 'assets/icons/scroll-mode.svg';
  static const String pageMode = 'assets/icons/page-mode.svg';

  /// 收藏：五角星（描边 = 未收藏，实心 = 已收藏）。
  static const String star = 'assets/icons/star.svg';
  static const String starFilled = 'assets/icons/star-filled.svg';

  /// 点赞：爱心（描边 = 未赞，实心 = 已赞）。
  static const String heart = 'assets/icons/heart.svg';
  static const String heartFilled = 'assets/icons/heart-filled.svg';

  /// 评论 / 发送。
  static const String comment = 'assets/icons/comment.svg';
  static const String send = 'assets/icons/send.svg';
}

/// 插画（空态 / 错误态）。
abstract final class AppIllustrations {
  static const String emptySearch = 'assets/illustrations/empty-search.svg';
  static const String emptyDownload = 'assets/illustrations/empty-download.svg';
  static const String errorNetwork = 'assets/illustrations/error-network.svg';
}

/// SVG 图标组件：颜色继承 [IconTheme]/[Theme]，尺寸按 16 / 20 / 24 取用。
class SvgIcon extends StatelessWidget {
  const SvgIcon(
    this.asset, {
    super.key,
    this.size = 24,
    this.color,
    this.semanticLabel,
  });

  final String asset;
  final double size;
  final Color? color;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final resolved = color ??
        IconTheme.of(context).color ??
        Theme.of(context).colorScheme.onSurface;
    return SvgPicture.asset(
      asset,
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(resolved, BlendMode.srcIn),
      excludeFromSemantics: semanticLabel == null,
      semanticsLabel: semanticLabel,
    );
  }
}

/// SVG 插画（空态 / 错误态），保持原始配色，不做 srcIn 重着色。
class SvgIllustration extends StatelessWidget {
  const SvgIllustration(
    this.asset, {
    super.key,
    this.width = 160,
    this.height = 120,
  });

  final String asset;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(asset, width: width, height: height);
  }
}
