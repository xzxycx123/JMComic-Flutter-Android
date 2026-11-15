import 'package:flutter/material.dart';

/// 位图素材入口（只放品牌 / 加载 / 角标 / 二维码这类"图"，图标仍走 assets/icons/*.svg）。
///
/// 来源：`img/` 目录（品牌图标与加载动画），由 `tools/build_app_assets.py` 派生到
/// `assets/images/`；规则见 assets/README.md。
abstract final class AppImages {
  /// 应用主图标 512（关于页 / 启动展示）。
  static const String appIcon = 'assets/images/app_icon.png';

  /// 品牌合成图（About 页横幅，含「禁漫天堂 18comic」标）。
  static const String brandBanner = 'assets/images/brand_banner.png';

  /// 黑猫加载动画（透明底 96px，列表/阅读器内联用）。
  static const String loadingCat = 'assets/images/loading_cat.gif';

  /// 黑猫加载动画大号（160px，首屏/详情用）。
  static const String loadingCatLarge = 'assets/images/loading_cat_large.gif';

  /// 加载动画首帧（静态兜底，动效关闭时用）。
  static const String loadingCatFrame = 'assets/images/loading_cat_frame.png';

  /// 官方 APP 下载二维码。
  static const String qrApp = 'assets/images/qr_app.png';

  /// 火箭（下载空态）。
  static const String rocket = 'assets/images/rocket.png';

  static const String badgeNew = 'assets/images/badge_new.png';
  static const String badgeHot = 'assets/images/badge_hot.png';
  static const String badgeDay = 'assets/images/badge_day.png';
  static const String badgeWeek = 'assets/images/badge_week.png';

  /// 按当前月份挑季节版方形吉祥物（默认回落到应用图标）。
  static String seasonalMark([DateTime? now]) {
    final month = (now ?? DateTime.now()).month;
    return switch (month) {
      1 => 'assets/images/mark_newyear.png',
      3 || 4 => 'assets/images/mark_sakura.png',
      5 => 'assets/images/mark_pink.png',
      10 => 'assets/images/mark_halloween.png',
      12 => 'assets/images/mark_xmas.png',
      _ => 'assets/images/mark_default.png',
    };
  }
}

/// 方形吉祥物标记（AppBar 左侧、我的页头像、关于页）。
class BrandMark extends StatelessWidget {
  const BrandMark({
    super.key,
    this.size = 26,
    this.radius = 8,
    this.asset,
    this.semanticLabel = 'JMComic',
  });

  final double size;
  final double radius;
  final String? asset;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Image.asset(
        asset ?? AppImages.seasonalMark(),
        width: size,
        height: size,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.medium,
        semanticLabel: semanticLabel,
        errorBuilder: (context, error, stackTrace) => SizedBox(
          width: size,
          height: size,
          child: ColoredBox(
            color: Theme.of(context).colorScheme.primaryContainer,
            child: Center(
              child: Text(
                'JM',
                style: TextStyle(
                  fontSize: size * 0.42,
                  fontWeight: FontWeight.w800,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 黑猫加载指示器：动图 + 一句状态文案（替代干巴巴的转圈）。
class MascotLoading extends StatelessWidget {
  const MascotLoading({
    super.key,
    this.label,
    this.size = 96,
    this.compact = false,
  });

  final String? label;
  final double size;

  /// 紧凑模式：不显示文案，只留小图标（列表内联用）。
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final asset = compact ? AppImages.loadingCat : AppImages.loadingCatLarge;
    // 紧凑模式按传入尺寸等比缩（阅读器里给 72，实际约 40 高）。
    final height = compact ? size * 0.55 : size;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Image.asset(
          asset,
          height: height,
          fit: BoxFit.contain,
          gaplessPlayback: true,
          semanticLabel: '加载中',
          errorBuilder: (context, error, stackTrace) => Image.asset(
            AppImages.loadingCatFrame,
            height: height,
            fit: BoxFit.contain,
          ),
        ),
        if (!compact && label != null) ...<Widget>[
          const SizedBox(height: 10),
          Text(
            label!,
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
        ],
      ],
    );
  }
}

/// 品牌横幅（About 页 / 首屏兜底）。
class BrandBanner extends StatelessWidget {
  const BrandBanner({super.key, this.height = 96, this.radius = 16});

  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: ColoredBox(
        color: scheme.surfaceContainer,
        child: Image.asset(
          AppImages.brandBanner,
          height: height,
          fit: BoxFit.contain,
          semanticLabel: 'JMComic 品牌图',
          errorBuilder: (context, error, stackTrace) => SizedBox(
            height: height,
            child: Center(
              child: Text('JMComic', style: Theme.of(context).textTheme.titleMedium),
            ),
          ),
        ),
      ),
    );
  }
}
