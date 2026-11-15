import 'dart:io';

import '../../core/utils/jm_id_parser.dart';
import '../local/download_store.dart';
import '../models/download_record.dart';
import '../sources/jm_api_client.dart';
import '../../features/download/engine/download_coordinator.dart';
import '../../features/download/engine/notification_service.dart';
import '../../features/download/engine/pdf_sink.dart';

/// 下载功能的门面：投递任务、订阅状态、打开产物。
class DownloadRepository {
  DownloadRepository({
    required Future<JmApi> Function() apiLoader,
    required DownloadHistory history,
    required PdfSink sink,
    DownloadNotificationService? notifications,
    Directory? workRoot,
  })  : _history = history,
        _sink = sink,
        _coordinator = DownloadCoordinator(
          apiLoader: apiLoader,
          history: history,
          sink: sink,
          notifications: notifications,
          workRoot: workRoot,
        );

  final DownloadHistory _history;
  final PdfSink _sink;
  final DownloadCoordinator _coordinator;

  List<DownloadRecord> get records => _history.records;

  Stream<List<DownloadRecord>> get stream => _history.stream;

  int get completedCount =>
      _history.records.where((record) => record.state == DownloadState.succeeded).length;

  int get activeCount => _history.records.where((record) => record.isActive).length;

  DownloadCoordinator get coordinator => _coordinator;

  Future<DownloadRecord> enqueue(String albumId) => _coordinator.enqueue(albumId);

  /// 批量输入文本 -> 去重保序 -> 逐条入队；返回新入队数量与去重数量。
  Future<({int added, int skipped, String? alreadyRunning})> enqueueInput(String input) async {
    final ids = parseJmIds(input);
    if (ids.isEmpty) return (added: 0, skipped: 0, alreadyRunning: null);

    var added = 0;
    var skipped = 0;
    String? running;
    for (final id in ids) {
      final existing = _history.records.where(
        (record) => record.albumId == id && record.isActive,
      );
      if (existing.isNotEmpty) {
        skipped++;
        running ??= id;
        continue;
      }
      await _coordinator.enqueue(id);
      added++;
    }
    return (added: added, skipped: skipped, alreadyRunning: running);
  }

  Future<void> cancel(String workId) => _coordinator.cancel(workId);

  Future<void> retry(String workId) => _coordinator.retry(workId);

  Future<void> remove(String workId) => _coordinator.remove(workId);

  Future<void> clearFinished() => _coordinator.clearFinished();

  Future<int> recoverInterrupted() => _coordinator.recoverInterrupted();

  Future<bool> open(DownloadRecord record) {
    final result = PdfExportResult(
      name: record.pdfName ?? '${record.albumId}.pdf',
      uri: record.pdfUri,
      path: record.pdfPath,
      isPublic: record.pdfUri?.startsWith('content://') ?? false,
    );
    return _sink.open(result);
  }

  Future<bool> openFile({String? uri, String? path, String? name}) {
    if (uri == null && path == null) return Future<bool>.value(false);
    return _sink.open(
      PdfExportResult(
        name: name ?? 'export.pdf',
        uri: uri,
        path: path,
        isPublic: uri?.startsWith('content://') ?? false,
      ),
    );
  }

  Future<String> describeLocation() => _sink.describeLocation();
}
