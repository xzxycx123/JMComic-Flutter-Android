import 'dart:math';

import '../../../core/network/api_exception.dart';

/// 取消信号：任务在任意 await 点检查，抛出 [JmCancelledException]。
class CancellationToken {
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() => _cancelled = true;

  void throwIfCancelled() {
    if (_cancelled) throw const JmCancelledException();
  }
}

/// 任务实体（workId + 车号 + 取消信号），状态落在 [DownloadRecord] 里。
class DownloadTask {
  DownloadTask({
    required this.workId,
    required this.albumId,
    CancellationToken? token,
  }) : token = token ?? CancellationToken();

  final String workId;
  final String albumId;
  final CancellationToken token;

  bool get isCancelled => token.isCancelled;
}

/// 生成唯一 workId。
///
/// 只用微秒时间戳会碰撞：批量入队时两次调用可能落在同一微秒，导致两个任务共用
/// 同一临时目录，互相删对方的页文件（表现为 PDF 缺页 / PathNotFound）。这里再拼
/// 一个进程内自增序号 + 随机数兜底。
int _workIdSequence = 0;
final Random _workIdRandom = Random();

String newWorkId() {
  _workIdSequence = (_workIdSequence + 1) & 0xFFFF;
  final stamp = DateTime.now().microsecondsSinceEpoch;
  final salt = _workIdRandom.nextInt(0x7FFFFFFF).toRadixString(36);
  return 'w${stamp}_${_workIdSequence}_$salt';
}
