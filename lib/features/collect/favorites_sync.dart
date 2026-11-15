import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/favorites_repository.dart';
import 'collect_providers.dart';

/// 收藏同步的全局状态（登录页 / 收藏页 / 我的页共享一份，避免并发对账）。
class FavoriteSyncStatus {
  const FavoriteSyncStatus({
    this.busy = false,
    this.lastReport,
    this.lastError,
    this.lastAt,
  });

  final bool busy;
  final FavoriteSyncReport? lastReport;
  final String? lastError;
  final DateTime? lastAt;

  bool get hasRun => lastReport != null || lastError != null;

  FavoriteSyncStatus copyWith({
    bool? busy,
    FavoriteSyncReport? lastReport,
    String? lastError,
    DateTime? lastAt,
    bool clearError = false,
  }) =>
      FavoriteSyncStatus(
        busy: busy ?? this.busy,
        lastReport: lastReport ?? this.lastReport,
        lastError: clearError ? null : (lastError ?? this.lastError),
        lastAt: lastAt ?? this.lastAt,
      );
}

final NotifierProvider<FavoritesSyncNotifier, FavoriteSyncStatus>
    favoritesSyncProvider =
    NotifierProvider<FavoritesSyncNotifier, FavoriteSyncStatus>(
  FavoritesSyncNotifier.new,
);

/// 双向同步：先对账（云端 -> 本地），再推送 outbox（本地 -> 云端）。
///
/// 登录成功后由登录页自动调用一次（PLAN §7.10 / FAVORITES §7）。
class FavoritesSyncNotifier extends Notifier<FavoriteSyncStatus> {
  @override
  FavoriteSyncStatus build() => const FavoriteSyncStatus();

  Future<FavoriteSyncReport?> syncNow() async {
    if (state.busy) return null;
    state = state.copyWith(busy: true, clearError: true);
    try {
      final report = await ref.read(favoritesRepositoryProvider).sync();
      ref.read(favoritesItemsProvider.notifier).reload();
      await ref.read(accountSessionProvider.notifier).updateCount(report.serverCount);
      state = FavoriteSyncStatus(
        busy: false,
        lastReport: report,
        lastAt: DateTime.now(),
      );
      return report;
    } catch (error) {
      state = FavoriteSyncStatus(
        busy: false,
        lastReport: state.lastReport,
        lastError: '$error',
        lastAt: DateTime.now(),
      );
      return null;
    }
  }

  /// 本地有、云端没有的收藏还需要补推时用（登录后先对账再补推）。
  Future<int> pushPending() async {
    try {
      final result = await ref.read(favoritesRepositoryProvider).pushOutbox();
      ref.read(favoritesItemsProvider.notifier).reload();
      return result.pushed;
    } catch (_) {
      return 0;
    }
  }
}
