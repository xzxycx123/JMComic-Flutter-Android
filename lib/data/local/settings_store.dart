import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';

import '../../core/utils/file_names.dart';
import 'hive_init.dart';

/// 外观模式（默认浅色，不是跟随系统）。
enum AppThemeMode {
  light('light', '浅色'),
  dark('dark', '深色'),
  system('system', '跟随系统');

  const AppThemeMode(this.code, this.label);

  final String code;
  final String label;

  ThemeMode get themeMode => switch (this) {
        AppThemeMode.light => ThemeMode.light,
        AppThemeMode.dark => ThemeMode.dark,
        AppThemeMode.system => ThemeMode.system,
      };

  static AppThemeMode fromCode(String? code) {
    for (final mode in AppThemeMode.values) {
      if (mode.code == code) return mode;
    }
    return AppThemeMode.light;
  }
}

/// 界面材质（与浅色 / 深色模式独立，默认保留 Metal）。
enum AppInterfaceStyle {
  metal('metal', 'Metal', '经典 Metal 界面与悬浮 Dock'),
  liquidGlass('liquidGlass', 'LiquidGlass', 'iOS 27同款 液态玻璃、折射与动态光影');

  const AppInterfaceStyle(this.code, this.label, this.description);

  final String code;
  final String label;
  final String description;

  static AppInterfaceStyle fromCode(String? code) {
    for (final style in AppInterfaceStyle.values) {
      if (style.code == code) return style;
    }
    return AppInterfaceStyle.metal;
  }
}

/// 应用设置（界面材质、明暗模式、阅读与网络偏好）。
class AppSettings {
  const AppSettings({
    this.themeMode = AppThemeMode.light,
    this.interfaceStyle = AppInterfaceStyle.metal,
    this.defaultReaderMode = 'paged',
    this.pageTurnAnimation = true,
    this.autoSwitchHost = true,
    this.rememberPassword = true,
    this.saveImagePath = defaultSaveImageDir,
  });

  final AppThemeMode themeMode;
  final AppInterfaceStyle interfaceStyle;

  /// 'paged'（左右翻页） / 'vertical'（上下滚动）。
  final String defaultReaderMode;
  final bool pageTurnAnimation;
  final bool autoSwitchHost;

  /// 记住密码（系统密钥库）+ cookie 失效时自动重登。默认开：不然退出 App 就掉登录。
  final bool rememberPassword;

  /// 阅读器「下载当页图片」的保存目录（相对公共存储，默认 `Pictures/JMComicDownloader/`）。
  final String saveImagePath;

  AppSettings copyWith({
    AppThemeMode? themeMode,
    AppInterfaceStyle? interfaceStyle,
    String? defaultReaderMode,
    bool? pageTurnAnimation,
    bool? autoSwitchHost,
    bool? rememberPassword,
    String? saveImagePath,
  }) =>
      AppSettings(
        themeMode: themeMode ?? this.themeMode,
        interfaceStyle: interfaceStyle ?? this.interfaceStyle,
        defaultReaderMode: defaultReaderMode ?? this.defaultReaderMode,
        pageTurnAnimation: pageTurnAnimation ?? this.pageTurnAnimation,
        autoSwitchHost: autoSwitchHost ?? this.autoSwitchHost,
        rememberPassword: rememberPassword ?? this.rememberPassword,
        saveImagePath: saveImagePath ?? this.saveImagePath,
      );
}

/// 设置读写（Hive 同步 API，UI 层通过 provider 订阅）。
class SettingsStore {
  SettingsStore(this._box);

  static const String _keyThemeMode = 'themeMode';
  static const String _keyInterfaceStyle = 'interfaceStyle';
  static const String _keyReaderMode = 'readerMode';
  static const String _keyPageTurnAnimation = 'pageTurnAnimation';
  static const String _keyAutoSwitchHost = 'autoSwitchHost';
  static const String _keyRememberPassword = 'rememberPassword';
  static const String _keySaveImagePath = 'saveImagePath';

  final Box<dynamic> _box;

  AppSettings read() => AppSettings(
        themeMode: AppThemeMode.fromCode(_box.get(_keyThemeMode) as String?),
        interfaceStyle:
            AppInterfaceStyle.fromCode(_box.get(_keyInterfaceStyle) as String?),
        defaultReaderMode: (_box.get(_keyReaderMode) as String?) ?? 'paged',
        pageTurnAnimation: (_box.get(_keyPageTurnAnimation) as bool?) ?? true,
        autoSwitchHost: (_box.get(_keyAutoSwitchHost) as bool?) ?? true,
        rememberPassword: (_box.get(_keyRememberPassword) as bool?) ?? true,
        saveImagePath: normalizeSaveDir(
          (_box.get(_keySaveImagePath) as String?) ?? defaultSaveImageDir,
        ),
      );

  Future<void> write(AppSettings settings) async {
    await _box.put(_keyThemeMode, settings.themeMode.code);
    await _box.put(_keyInterfaceStyle, settings.interfaceStyle.code);
    await _box.put(_keyReaderMode, settings.defaultReaderMode);
    await _box.put(_keyPageTurnAnimation, settings.pageTurnAnimation);
    await _box.put(_keyAutoSwitchHost, settings.autoSwitchHost);
    await _box.put(_keyRememberPassword, settings.rememberPassword);
    await _box.put(_keySaveImagePath, settings.saveImagePath);
  }
}

final Provider<SettingsStore> settingsStoreProvider = Provider<SettingsStore>(
  (ref) => SettingsStore(Hive.box<dynamic>(HiveBoxes.settings)),
);

final NotifierProvider<SettingsNotifier, AppSettings> settingsProvider =
    NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);

class SettingsNotifier extends Notifier<AppSettings> {
  @override
  AppSettings build() => ref.read(settingsStoreProvider).read();

  Future<void> _commit(AppSettings next) async {
    state = next;
    await ref.read(settingsStoreProvider).write(next);
  }

  Future<void> setThemeMode(AppThemeMode mode) =>
      _commit(state.copyWith(themeMode: mode));

  Future<void> setInterfaceStyle(AppInterfaceStyle style) =>
      _commit(state.copyWith(interfaceStyle: style));

  Future<void> setDefaultReaderMode(String mode) =>
      _commit(state.copyWith(defaultReaderMode: mode));

  Future<void> setPageTurnAnimation(bool enabled) =>
      _commit(state.copyWith(pageTurnAnimation: enabled));

  Future<void> setAutoSwitchHost(bool enabled) =>
      _commit(state.copyWith(autoSwitchHost: enabled));

  Future<void> setRememberPassword(bool enabled) =>
      _commit(state.copyWith(rememberPassword: enabled));

  /// 保存图片目录（自动去掉首尾斜杠，空值回落默认目录）。
  Future<void> setSaveImagePath(String path) =>
      _commit(state.copyWith(saveImagePath: normalizeSaveDir(path)));
}

/// 便捷派生：MaterialApp 的 ThemeMode。
final Provider<ThemeMode> themeModeProvider = Provider<ThemeMode>(
  (ref) => ref.watch(settingsProvider).themeMode.themeMode,
);

/// 便捷派生：Metal / LiquidGlass 界面材质。
final Provider<AppInterfaceStyle> interfaceStyleProvider =
    Provider<AppInterfaceStyle>(
  (ref) => ref.watch(settingsProvider).interfaceStyle,
);
