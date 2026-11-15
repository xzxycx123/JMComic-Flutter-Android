import 'package:flutter/material.dart';

/// 字号字重表（PLAN §7.1/§7.3 的尺寸口径集中在这里）。
abstract final class AppTypography {
  // 首页字标
  static const TextStyle wordmark = TextStyle(
    fontSize: 21,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.5,
    height: 1.1,
  );

  // 页面标题 / 详情标题
  static const TextStyle displayTitle = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w700,
    height: 1.25,
  );

  static const TextStyle title = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w700,
    height: 1.3,
  );

  static const TextStyle sectionTitle = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w700,
    height: 1.3,
  );

  static const TextStyle cardTitle = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    height: 1.32,
  );

  static const TextStyle body = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.5,
  );

  static const TextStyle bodyStrong = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    height: 1.4,
  );

  static const TextStyle caption = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    height: 1.4,
  );

  static const TextStyle micro = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w500,
    height: 1.35,
  );

  /// 数字 / 计数（等宽感，避免进度跳动时抖动）。
  static const TextStyle numeric = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w600,
    height: 1.2,
    fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
  );

  static TextTheme textTheme(Color ink, Color inkVariant) {
    return TextTheme(
      displaySmall: displayTitle.copyWith(color: ink),
      headlineSmall: title.copyWith(color: ink),
      titleMedium: sectionTitle.copyWith(color: ink),
      titleSmall: cardTitle.copyWith(color: ink),
      bodyLarge: body.copyWith(color: ink),
      bodyMedium: body.copyWith(color: ink),
      bodySmall: caption.copyWith(color: inkVariant),
      labelLarge: bodyStrong.copyWith(color: ink),
      labelMedium: caption.copyWith(color: inkVariant),
      labelSmall: micro.copyWith(color: inkVariant),
    );
  }
}
