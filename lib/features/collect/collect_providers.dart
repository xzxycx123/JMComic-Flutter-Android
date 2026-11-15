import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';

import '../../data/local/favorites_store.dart';
import '../../data/local/hive_init.dart';
import '../../data/local/session_store.dart';
import '../../data/models/account_session.dart';
import '../../data/models/favorite_item.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/favorites_repository.dart';
import '../../core/di/providers.dart';

/// 收藏 box 的存储层（per-album 账本 + 文件夹 + outbox）。
final Provider<FavoritesStore> favoritesStoreProvider = Provider<FavoritesStore>(
  (ref) => FavoritesStore(
    favorites: Hive.box<dynamic>(HiveBoxes.favorites),
    folders: Hive.box<dynamic>(HiveBoxes.favoriteFolders),
    outbox: Hive.box<dynamic>(HiveBoxes.favoriteOutbox),
  ),
);

final Provider<SessionStore> sessionStoreProvider = Provider<SessionStore>(
  (ref) => SessionStore(Hive.box<dynamic>(HiveBoxes.session)),
);

final Provider<AuthRepository> authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(
    api: ref.watch(jmApiProvider),
    session: ref.watch(sessionStoreProvider),
    favorites: ref.watch(favoritesStoreProvider),
  ),
);

final AsyncNotifierProvider<AccountSessionNotifier, AccountSession> accountSessionProvider =
    AsyncNotifierProvider<AccountSessionNotifier, AccountSession>(
  AccountSessionNotifier.new,
);

class AccountSessionNotifier extends AsyncNotifier<AccountSession> {
  @override
  Future<AccountSession> build() async {
    final repository = ref.watch(authRepositoryProvider);
    final session = await repository.restore();
    // 会话恢复成功后把 cookie 落盘（可能已被服务端刷新）。
    if (session.state == SessionState.valid) {
      await repository.persistCookies();
    }
    return session;
  }

  Future<void> login(String username, String password) async {
    state = const AsyncValue<AccountSession>.loading();
    state = await AsyncValue.guard(
      () => ref.read(authRepositoryProvider).login(username: username, password: password),
    );
    if (state.hasValue) {
      ref.read(favoritesItemsProvider.notifier).reload();
    }
  }

  Future<void> logout() async {
    await ref.read(authRepositoryProvider).logout();
    state = const AsyncValue<AccountSession>.data(AccountSession.local);
    ref.read(favoritesItemsProvider.notifier).reload();
  }

  /// 同步完成后回写收藏计数。
  Future<void> updateCount(int favoritesCount) async {
    final store = ref.read(sessionStoreProvider);
    final next = store.readSession().copyWith(favoritesCount: favoritesCount);
    await store.writeSession(next);
    state = AsyncValue<AccountSession>.data(next);
  }

  Future<void> markNeedsLogin() async {
    final next = await ref.read(authRepositoryProvider).markNeedsLogin();
    state = AsyncValue<AccountSession>.data(next);
  }
}

final Provider<FavoritesRepository> favoritesRepositoryProvider = Provider<FavoritesRepository>(
  (ref) => FavoritesRepository(
    api: ref.watch(jmApiProvider),
    store: ref.watch(favoritesStoreProvider),
    session: ref.watch(sessionStoreProvider),
  ),
);

/// 收藏条目（本地账本快照；每次写操作后调用 [reload]）。
final NotifierProvider<FavoritesItemsNotifier, List<FavoriteItem>> favoritesItemsProvider =
    NotifierProvider<FavoritesItemsNotifier, List<FavoriteItem>>(FavoritesItemsNotifier.new);

class FavoritesItemsNotifier extends Notifier<List<FavoriteItem>> {
  @override
  List<FavoriteItem> build() => ref.watch(favoritesStoreProvider).items;

  void reload() => state = ref.read(favoritesStoreProvider).items;
}

final Provider<List<FavoriteFolder>> favoritesFoldersProvider = Provider<List<FavoriteFolder>>(
  (ref) => ref.watch(favoritesStoreProvider).folders,
);

/// 收藏 id 集合（详情页书签状态用）。
final Provider<Set<String>> favoriteIdsProvider = Provider<Set<String>>(
  (ref) => ref.watch(favoritesItemsProvider).map((item) => item.albumId).toSet(),
);

final Provider<int> favoriteCountProvider = Provider<int>(
  (ref) => ref.watch(favoritesItemsProvider).length,
);
