import 'package:flutter/foundation.dart';

/// [compute] 的薄封装：统一 isolate 入口命名，测试里可替换。
Future<R> runInIsolate<M, R>(ComputeCallback<M, R> callback, M message) =>
    compute(callback, message);
