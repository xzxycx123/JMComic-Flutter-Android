import 'package:flutter/foundation.dart';

import '../config/app_config.dart';

/// 统一日志：release 只保留 warn/error，debug 全开（可用 --dart-define=JM_VERBOSE=true 强制）。
abstract final class Log {
  static bool get _enabled => kDebugMode || AppConfig.verboseLog;

  static void d(String message) {
    if (_enabled) {
      debugPrint('[JM][D] $message');
    }
  }

  static void i(String message) {
    if (_enabled) {
      debugPrint('[JM][I] $message');
    }
  }

  static void w(String message) {
    if (_enabled) {
      debugPrint('[JM][W] $message');
    }
  }

  static void e(String message, [Object? error, StackTrace? stackTrace]) {
    debugPrint('[JM][E] $message${error == null ? '' : ' :: $error'}');
    if (_enabled && stackTrace != null) {
      debugPrint(stackTrace.toString());
    }
  }
}
