import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';

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

/// 应用设置（主题、默认阅读模式、翻页动画、自动切换线路、自动登录）。
class AppSettings {
  const AppSettings({
    this.themeMode = AppThemeMode.light,
    this.defaultReaderMode = 'paged',
    this.pageTurnAnimation = true,
    this.autoSwitchHost = true,
    this.rememberPassword = true,
  });

  final AppThemeMode themeMode;

  /// 'paged'（左右翻页） / 'vertical'（上下滚动）。
  final String defaultReaderMode;
  final bool pageTurnAnimation;
  final bool autoSwitchHost;

  /// 记住密码（系统密钥库）+ cookie 失效时自动重登。默认开：不然退出 App 就掉登录。
  final bool rememberPassword;

  AppSettings copyWith({
    AppThemeMode? themeMode,
    String? defaultReaderMode,
    bool? pageTurnAnimation,
    bool? autoSwitchHost,
    bool? rememberPassword,
  }) =>
      AppSettings(
        themeMode: themeMode ?? this.themeMode,
        defaultReaderMode: defaultReaderMode ?? this.defaultReaderMode,
        pageTurnAnimation: pageTurnAnimation ?? this.pageTurnAnimation,
        autoSwitchHost: autoSwitchHost ?? this.autoSwitchHost,
        rememberPassword: rememberPassword ?? this.rememberPassword,
      );
}

/// 设置读写（Hive 同步 API，UI 层通过 provider 订阅）。
class SettingsStore {
  SettingsStore(this._box);

  static const String _keyThemeMode = 'themeMode';
  static const String _keyReaderMode = 'readerMode';
  static const String _keyPageTurnAnimation = 'pageTurnAnimation';
  static const String _keyAutoSwitchHost = 'autoSwitchHost';
  static const String _keyRememberPassword = 'rememberPassword';

  final Box<dynamic> _box;

  AppSettings read() => AppSettings(
        themeMode: AppThemeMode.fromCode(_box.get(_keyThemeMode) as String?),
        defaultReaderMode: (_box.get(_keyReaderMode) as String?) ?? 'paged',
        pageTurnAnimation: (_box.get(_keyPageTurnAnimation) as bool?) ?? true,
        autoSwitchHost: (_box.get(_keyAutoSwitchHost) as bool?) ?? true,
        rememberPassword: (_box.get(_keyRememberPassword) as bool?) ?? true,
      );

  Future<void> write(AppSettings settings) async {
    await _box.put(_keyThemeMode, settings.themeMode.code);
    await _box.put(_keyReaderMode, settings.defaultReaderMode);
    await _box.put(_keyPageTurnAnimation, settings.pageTurnAnimation);
    await _box.put(_keyAutoSwitchHost, settings.autoSwitchHost);
    await _box.put(_keyRememberPassword, settings.rememberPassword);
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

  Future<void> setDefaultReaderMode(String mode) =>
      _commit(state.copyWith(defaultReaderMode: mode));

  Future<void> setPageTurnAnimation(bool enabled) =>
      _commit(state.copyWith(pageTurnAnimation: enabled));

  Future<void> setAutoSwitchHost(bool enabled) =>
      _commit(state.copyWith(autoSwitchHost: enabled));

  Future<void> setRememberPassword(bool enabled) =>
      _commit(state.copyWith(rememberPassword: enabled));
}

/// 便捷派生：MaterialApp 的 ThemeMode。
final Provider<ThemeMode> themeModeProvider = Provider<ThemeMode>(
  (ref) => ref.watch(settingsProvider).themeMode.themeMode,
);
