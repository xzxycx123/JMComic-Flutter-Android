import 'json_field.dart';

/// 下载任务状态（与 JmScript/DownloadRecord.kt 的字符串常量同值，便于跨端核对）。
enum DownloadState {
  queued('QUEUED', '排队中'),
  running('RUNNING', '下载中'),
  succeeded('SUCCEEDED', '已完成'),
  failed('FAILED', '失败'),
  cancelled('CANCELLED', '已取消');

  const DownloadState(this.code, this.label);

  final String code;
  final String label;

  static DownloadState fromCode(String? code) {
    for (final state in DownloadState.values) {
      if (state.code == code) return state;
    }
    return DownloadState.queued;
  }
}

/// 下载记录（字段与 JmScript/history/DownloadRecord.kt 逐项对齐）。
class DownloadRecord {
  const DownloadRecord({
    required this.workId,
    required this.albumId,
    this.title = '',
    this.state = DownloadState.queued,
    this.status = '',
    this.detail = '',
    this.done = 0,
    this.total = 0,
    this.percent = 0,
    this.pdfPath,
    this.pdfUri,
    this.pdfName,
    this.pageCount = 0,
    this.error,
    this.createdAt = 0,
    this.updatedAt = 0,
  });

  final String workId;
  final String albumId;
  final String title;
  final DownloadState state;

  /// 面向用户的一句话，如「已下载 12/48 页」。
  final String status;

  /// 次要信息：当前线路 / 错误原因。
  final String detail;
  final int done;
  final int total;
  final int percent;

  /// 落盘绝对路径（公共 Documents 拿不到时的降级路径）。
  final String? pdfPath;

  /// content:// 或 file:// URI。
  final String? pdfUri;
  final String? pdfName;
  final int pageCount;
  final String? error;
  final int createdAt;
  final int updatedAt;

  bool get isActive =>
      state == DownloadState.queued || state == DownloadState.running;

  bool get isFinished => !isActive;

  bool get isOpenable => state == DownloadState.succeeded && (pdfUri != null || pdfPath != null);

  String get displayTitle => title.trim().isEmpty ? 'JM$albumId' : title.trim();

  Duration? get elapsed => (createdAt <= 0 || updatedAt <= 0)
      ? null
      : Duration(milliseconds: updatedAt - createdAt);

  DownloadRecord copyWith({
    String? albumId,
    String? title,
    DownloadState? state,
    String? status,
    String? detail,
    int? done,
    int? total,
    int? percent,
    String? pdfPath,
    String? pdfUri,
    String? pdfName,
    int? pageCount,
    String? error,
    int? createdAt,
    int? updatedAt,
    bool clearError = false,
    bool clearPdf = false,
  }) {
    return DownloadRecord(
      workId: workId,
      albumId: albumId ?? this.albumId,
      title: title ?? this.title,
      state: state ?? this.state,
      status: status ?? this.status,
      detail: detail ?? this.detail,
      done: done ?? this.done,
      total: total ?? this.total,
      percent: percent ?? this.percent,
      pdfPath: clearPdf ? null : (pdfPath ?? this.pdfPath),
      pdfUri: clearPdf ? null : (pdfUri ?? this.pdfUri),
      pdfName: clearPdf ? null : (pdfName ?? this.pdfName),
      pageCount: pageCount ?? this.pageCount,
      error: clearError ? null : (error ?? this.error),
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory DownloadRecord.fromJson(Map<String, dynamic> json) => DownloadRecord(
        workId: asStringOr(json['workId'], ''),
        albumId: asStringOr(json['albumId'], ''),
        title: asStringOr(json['title'], ''),
        state: DownloadState.fromCode(asString(json['state'])),
        status: asStringOr(json['status'], ''),
        detail: asStringOr(json['detail'], ''),
        done: asInt(json['done']),
        total: asInt(json['total']),
        percent: asInt(json['percent']),
        pdfPath: asString(json['pdfPath']),
        pdfUri: asString(json['pdfUri']),
        pdfName: asString(json['pdfName']),
        pageCount: asInt(json['pageCount']),
        error: asString(json['error']),
        createdAt: asInt(json['createdAt']),
        updatedAt: asInt(json['updatedAt']),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'workId': workId,
        'albumId': albumId,
        'title': title,
        'state': state.code,
        'status': status,
        'detail': detail,
        'done': done,
        'total': total,
        'percent': percent,
        'pdfPath': pdfPath,
        'pdfUri': pdfUri,
        'pdfName': pdfName,
        'pageCount': pageCount,
        'error': error,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
      };
}
