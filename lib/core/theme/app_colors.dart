import 'package:flutter/material.dart';

/// 固定色板（PLAN §7.1 定稿，禁止在 widget 里写死 hex）。
///
/// 浅色「白橙」为默认外观，深色为 `#141413` 底 + `#FAF9F5` 字。
/// 两套都是显式 token，不从 seed 反推。
abstract final class AppColors {
  // ---------------------------------------------------------------- 浅色（白橙）
  static const Color lightBg = Color(0xFFFFFFFF);
  static const Color lightSurfaceContainer = Color(0xFFFBF8F3);
  static const Color lightSurfaceContainerHigh = Color(0xFFF5F0E8);
  static const Color lightOutline = Color(0xFFEBE3D8);
  static const Color lightOutlineVariant = Color(0xFFF2ECE2);
  static const Color lightPrimary = Color(0xFFF26B0F);
  static const Color lightPrimaryContainer = Color(0xFFFFE8D5);
  static const Color lightOnPrimaryContainer = Color(0xFF7A3200);
  static const Color lightSecondary = Color(0xFFE89B2C);
  static const Color lightInk = Color(0xFF141413);
  static const Color lightInkVariant = Color(0xFF6B6862);
  static const Color lightError = Color(0xFFC6413A);

  // ---------------------------------------------------------------- 深色
  static const Color darkBg = Color(0xFF141413);
  static const Color darkSurface = Color(0xFF1B1B19);
  static const Color darkSurfaceContainer = Color(0xFF232320);
  static const Color darkSurfaceContainerHigh = Color(0xFF2C2C28);
  static const Color darkOutline = Color(0xFF3A3A35);
  static const Color darkOutlineVariant = Color(0xFF2A2A26);
  static const Color darkPrimary = Color(0xFFFF8A3D);
  static const Color darkOnPrimary = Color(0xFF1A0F05);
  static const Color darkPrimaryContainer = Color(0xFF3B2412);
  static const Color darkOnPrimaryContainer = Color(0xFFFFD9BE);
  static const Color darkSecondary = Color(0xFFFFB25C);
  static const Color darkInk = Color(0xFFFAF9F5);
  static const Color darkInkVariant = Color(0xFFA9A69D);
  static const Color darkError = Color(0xFFFF6B5E);

  // ---------------------------------------------------------------- 阅读器（恒定深色）
  static const Color readerBg = Color(0xFF0B0B0A);
  static const Color readerInk = Color(0xFFFAF9F5);

  // ---------------------------------------------------------------- 形状与阴影
  static const double radiusCard = 16;
  static const double radiusCover = 20;
  static const double radiusPanel = 24;
  static const double radiusPill = 999;

  /// 浅色阴影（深色不用阴影，改用 outline 描边）。
  static const Color lightShadow = Color(0x0F141413);

  static const ColorScheme lightScheme = ColorScheme(
    brightness: Brightness.light,
    primary: lightPrimary,
    onPrimary: Colors.white,
    primaryContainer: lightPrimaryContainer,
    onPrimaryContainer: lightOnPrimaryContainer,
    secondary: lightSecondary,
    onSecondary: Colors.white,
    tertiary: lightSecondary,
    onTertiary: Colors.white,
    surface: lightBg,
    onSurface: lightInk,
    surfaceContainer: lightSurfaceContainer,
    surfaceContainerHigh: lightSurfaceContainerHigh,
    surfaceContainerHighest: lightSurfaceContainerHigh,
    onSurfaceVariant: lightInkVariant,
    outline: lightOutline,
    outlineVariant: lightOutlineVariant,
    error: lightError,
    onError: Colors.white,
  );

  static const ColorScheme darkScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: darkPrimary,
    onPrimary: darkOnPrimary,
    primaryContainer: darkPrimaryContainer,
    onPrimaryContainer: darkOnPrimaryContainer,
    secondary: darkSecondary,
    onSecondary: darkOnPrimary,
    tertiary: darkSecondary,
    onTertiary: darkOnPrimary,
    surface: darkBg,
    onSurface: darkInk,
    surfaceContainer: darkSurfaceContainer,
    surfaceContainerHigh: darkSurfaceContainerHigh,
    surfaceContainerHighest: darkSurfaceContainerHigh,
    onSurfaceVariant: darkInkVariant,
    outline: darkOutline,
    outlineVariant: darkOutlineVariant,
    error: darkError,
    onError: darkOnPrimary,
  );
}
