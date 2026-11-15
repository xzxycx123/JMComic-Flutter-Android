/// 协议层 / 内容层异常。
///
/// 与 `JmScript/data/Models.kt` 对齐：
/// - [JmApiException] 可重试（网络 / 线路 / 解析失败），下载任务据此自动重试；
/// - [JmContentException] 不可重试（接口正常但内容不满足，如没有图片）。
sealed class JmException implements Exception {
  const JmException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => message;
}

/// 线路 / 网络层失败：换 host 重试、任务级重试都适用。
class JmApiException extends JmException {
  const JmApiException(super.message, {super.cause, this.network = true});

  /// false 表示"响应拿到了但不是预期的形状"（仍属可重试）。
  final bool network;
}

/// 接口正常但内容不满足：不重试，直接把可读原因抛给 UI。
class JmContentException extends JmException {
  const JmContentException(super.message, {super.cause});
}

/// 任务被用户取消（不是失败）。
class JmCancelledException extends JmException {
  const JmCancelledException([super.message = '已取消']);
}
