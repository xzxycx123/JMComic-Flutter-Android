import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/providers.dart';
import '../../data/models/download_record.dart';

/// 下载记录（历史流的最新快照）。
final NotifierProvider<DownloadRecordsNotifier, List<DownloadRecord>> downloadRecordsProvider =
    NotifierProvider<DownloadRecordsNotifier, List<DownloadRecord>>(DownloadRecordsNotifier.new);

class DownloadRecordsNotifier extends Notifier<List<DownloadRecord>> {
  @override
  List<DownloadRecord> build() {
    final history = ref.watch(downloadHistoryProvider);
    final subscription = history.stream.listen((records) => state = records);
    ref.onDispose(subscription.cancel);
    return history.records;
  }
}

/// 下载页分段筛选。
enum DownloadFilter {
  all('全部'),
  active('进行中'),
  finished('已完成');

  const DownloadFilter(this.label);

  final String label;
}

final StateProvider<DownloadFilter> downloadFilterProvider =
    StateProvider<DownloadFilter>((ref) => DownloadFilter.all);

/// 输入框文本（跨 tab 保留，切走再回不丢）。
final StateProvider<String> downloadInputProvider = StateProvider<String>((ref) => '');

final Provider<List<DownloadRecord>> filteredRecordsProvider = Provider<List<DownloadRecord>>((ref) {
  final records = ref.watch(downloadRecordsProvider);
  final filter = ref.watch(downloadFilterProvider);
  return switch (filter) {
    DownloadFilter.all => records,
    DownloadFilter.active => records.where((record) => record.isActive).toList(growable: false),
    DownloadFilter.finished => records.where((record) => record.isFinished).toList(growable: false),
  };
});

final Provider<int> activeDownloadCountProvider = Provider<int>((ref) {
  return ref.watch(downloadRecordsProvider).where((record) => record.isActive).length;
});

final Provider<int> completedDownloadCountProvider = Provider<int>((ref) {
  return ref
      .watch(downloadRecordsProvider)
      .where((record) => record.state == DownloadState.succeeded)
      .length;
});
