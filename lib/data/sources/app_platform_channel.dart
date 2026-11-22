import 'package:flutter/services.dart';

import '../../core/utils/logger.dart';

/// 原生侧小能力（`jm_comic/app` 通道）。
///
/// - `versionName`：读 PackageManager 里的真实 versionName（来自 pubspec），
///   比写死常量可靠（手动 bump 版本时不会忘）。
/// - `openUrl`：拉起系统浏览器 / 安装器（Dart 侧没有 url_launcher）。
class AppPlatformChannel {
  AppPlatformChannel({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('jm_comic/app');

  final MethodChannel _channel;

  /// 安装包 versionName；取不到返回 null（调用方回落到 `AppConfig.appVersion`）。
  Future<String?> versionName() async {
    try {
      final value = await _channel.invokeMethod<String>('versionName');
      final text = value?.trim();
      return (text == null || text.isEmpty) ? null : text;
    } on MissingPluginException {
      return null;
    } catch (error) {
      Log.i('读取 versionName 失败：$error');
      return null;
    }
  }

  /// 用系统默认应用打开 [url]（浏览器 / 安装器）。
  Future<bool> openUrl(String url) async {
    if (url.isEmpty) return false;
    try {
      final ok = await _channel.invokeMethod<bool>(
        'openUrl',
        <String, dynamic>{'url': url},
      );
      return ok ?? false;
    } on MissingPluginException {
      return false;
    } catch (error) {
      Log.i('打开链接失败：$error');
      return false;
    }
  }
}
