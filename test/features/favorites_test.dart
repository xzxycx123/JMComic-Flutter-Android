import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:jm_comic/data/local/credential_store.dart';
import 'package:jm_comic/data/local/favorites_store.dart';
import 'package:jm_comic/data/local/hive_init.dart';
import 'package:jm_comic/data/local/session_store.dart';
import 'package:jm_comic/data/models/account_session.dart';
import 'package:jm_comic/data/models/favorite_item.dart';
import 'package:jm_comic/data/models/jm_album_summary.dart';
import 'package:jm_comic/data/repositories/auth_repository.dart';
import 'package:jm_comic/data/repositories/favorites_repository.dart';

import '../helpers/fixtures.dart';
import '../helpers/test_env.dart';

late FavoritesStore store;
late SessionStore sessions;

FavoritesStore buildStore() => FavoritesStore(
      favorites: Hive.box<dynamic>(HiveBoxes.favorites),
      folders: Hive.box<dynamic>(HiveBoxes.favoriteFolders),
      outbox: Hive.box<dynamic>(HiveBoxes.favoriteOutbox),
    );

SessionStore buildSessions() => SessionStore(Hive.box<dynamic>(HiveBoxes.session));

const summary1 = JmAlbumSummary(id: '1', title: '一本 One');
const summary2 = JmAlbumSummary(id: '2', title: '两本 Two');
const summary3 = JmAlbumSummary(id: '3', title: '三本 Three');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initTestStores();
  });

  setUp(() async {
    await clearTestBoxes();
    store = buildStore();
    sessions = buildSessions();
    await store.migrateIfNeeded();
  });

  group('FavoritesStore', () {
    test('老格式 ids 迁移成 per-album 记录（幂等）', () async {
      await Hive.box<dynamic>(HiveBoxes.favorites)
          .put('ids', <String>['11', '12']);
      await store.migrateIfNeeded();

      expect(store.items.map((item) => item.albumId).toSet(), <String>{'11', '12'});
      expect(Hive.box<dynamic>(HiveBoxes.favorites).containsKey('ids'), isFalse);

      await store.migrateIfNeeded();
      expect(store.count, 2);
    });

    test('默认文件夹恒存在，可新建 / 归档 / 删除', () async {
      expect(store.folders.first.id, 'default');
      final folder = await store.createFolder('私藏');
      await store.addFromSummary(summary1, folderId: folder.id);
      expect(store.item('1')!.folderIds, contains(folder.id));

      await store.deleteFolder(folder.id);
      expect(store.folders.any((item) => item.id == folder.id), isFalse);
      expect(store.item('1')!.folderIds, <String>['default']);
    });

    test('outbox 同一 albumId 只保留最后一次操作', () async {
      await store.enqueue(FavoriteOp.add, '9');
      await store.enqueue(FavoriteOp.remove, '9');
      await store.enqueue(FavoriteOp.add, '9');

      expect(store.outbox.length, 1);
      expect(store.outbox.first.op, FavoriteOp.add);
    });
  });

  group('FavoritesRepository（本地）', () {
    test('未登录：只写本地，不入 outbox', () async {
      final api = FakeJmApi();
      final repository = FavoritesRepository(api: api, store: store, session: sessions);

      final added = await repository.toggle(summary1);
      expect(added, isTrue);
      expect(repository.isFavorite('1'), isTrue);
      expect(store.item('1')!.sync, FavoriteSyncState.localOnly);
      expect(store.outbox, isEmpty);
      expect(api.serverFavorites, isEmpty);

      final removed = await repository.toggle(summary1);
      expect(removed, isFalse);
      expect(repository.isFavorite('1'), isFalse);
    });

    test('已登录：乐观更新 + 入 outbox 并推送成功', () async {
      await sessions.writeSession(
        const AccountSession(uid: 42, username: 'tester', state: SessionState.valid),
      );
      final api = FakeJmApi(loggedIn: true);
      final repository = FavoritesRepository(api: api, store: store, session: sessions);

      await repository.toggle(summary2);
      // 等后台 push 完成（unawaited）
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(api.serverFavorites, contains('2'));
      expect(store.item('2')!.sync, FavoriteSyncState.synced);
      expect(store.outbox, isEmpty);
    });
  });

  group('FavoritesRepository.sync', () {
    test('对账：服务端独有入库、本地独有补推', () async {
      await sessions.writeSession(
        const AccountSession(uid: 42, username: 'tester', state: SessionState.valid),
      );
      final api = FakeJmApi(loggedIn: true, serverFavorites: <String>{'1'});
      await store.addFromSummary(summary2, sync: FavoriteSyncState.localOnly);
      final repository = FavoritesRepository(api: api, store: store, session: sessions);

      final report = await repository.sync();

      expect(report.serverCount, 1);
      expect(store.contains('1'), isTrue, reason: '服务端独有的要落到本地');
      expect(store.item('1')!.sync, FavoriteSyncState.synced);
      expect(api.serverFavorites, contains('2'), reason: '本地独有的要补推');
      expect(store.item('2')!.sync, FavoriteSyncState.synced);
      expect(store.outbox, isEmpty);
    });

    test('toggle 被服务端反向执行时自愈（再补一次）', () async {
      await sessions.writeSession(
        const AccountSession(uid: 42, username: 'tester', state: SessionState.valid),
      );
      final api = FakeJmApi(loggedIn: true, forcedToggleType: 'remove');
      await store.addFromSummary(summary3, sync: FavoriteSyncState.localOnly);
      await store.enqueue(FavoriteOp.add, '3');
      final repository = FavoritesRepository(api: api, store: store, session: sessions);

      final report = await repository.pushOutbox();

      expect(report.conflicts, 1);
      expect(api.serverFavorites, contains('3'), reason: '补发一次后服务端应为已收藏');
      expect(store.item('3')!.sync, FavoriteSyncState.conflict);
      expect(store.outbox, isEmpty);
    });

    test('未登录时 sync 直接报错，不动本地', () async {
      final repository = FavoritesRepository(
        api: FakeJmApi(),
        store: store,
        session: sessions,
      );
      await store.addFromSummary(summary1);
      expect(() => repository.sync(), throwsA(isA<Exception>()));
      expect(store.contains('1'), isTrue);
    });
  });

  group('AuthRepository', () {
    test('登录成功：写会话与 cookie，不落密码', () async {
      final api = FakeJmApi();
      final repository = AuthRepository(api: api, session: sessions, favorites: store);

      final session = await repository.login(username: 'tester', password: 'pw123456');
      expect(session.uid, 42);
      expect(session.state, SessionState.valid);
      expect(sessions.readSession().username, 'tester');
      expect(sessions.readCookies()['AVS'], 'fake-avs');
      // 会话 JSON 里不应出现密码字段
      expect(sessions.readSession().toJson().toString().contains('pw123456'), isFalse);
    });

    test('冷启动：cookie 有效则恢复，失效则 needsLogin', () async {
      final api = FakeJmApi(loggedIn: false);
      final repository = AuthRepository(api: api, session: sessions, favorites: store);

      await sessions.writeSession(
        const AccountSession(uid: 42, username: 'tester', state: SessionState.valid),
      );
      await sessions.writeCookies(<String, String>{'AVS': 'stale'});
      final restored = await repository.restore();
      expect(restored.state, SessionState.needsLogin);

      api.loggedIn = true;
      await sessions.writeSession(
        const AccountSession(uid: 42, username: 'tester', state: SessionState.needsLogin),
      );
      final again = await repository.restore();
      expect(again.state, SessionState.valid);
    });

    test('冷启动：非鉴权业务错误不把用户踢下线（0.3.1 回归）', () async {
      final api = FakeJmApi(loggedIn: true)
        ..favoritesError = 'JM 接口错误：服务器繁忙，请稍后再试';
      final repository = AuthRepository(api: api, session: sessions, favorites: store);

      await sessions.writeSession(
        const AccountSession(uid: 42, username: 'tester', state: SessionState.valid),
      );
      await sessions.writeCookies(<String, String>{'AVS': 'fresh'});

      final restored = await repository.restore();
      expect(restored.state, SessionState.valid);
      expect(restored.uid, 42);
    });

    test('冷启动 cookie 失效：用保存的密码自动重登（0.3.2）', () async {
      final vault = MemoryCredentialVault();
      await vault.save(
        const SavedCredential(username: 'tester', password: 'pw123456'),
      );
      final api = FakeJmApi(loggedIn: false);
      final repository = AuthRepository(
        api: api,
        session: sessions,
        favorites: store,
        vault: vault,
      );

      await sessions.writeSession(
        const AccountSession(uid: 42, username: 'tester', state: SessionState.valid),
      );
      await sessions.writeCookies(<String, String>{'AVS': 'expired'});

      final restored = await repository.restore();
      expect(restored.state, SessionState.valid);
      expect(restored.username, 'tester');
      expect(api.loginCalls, 1, reason: '应当用保存的密码重登一次');
    });

    test('关闭「记住密码」时不自动登录', () async {
      final vault = MemoryCredentialVault();
      await vault.save(
        const SavedCredential(username: 'tester', password: 'pw123456'),
      );
      final api = FakeJmApi(loggedIn: false);
      final repository = AuthRepository(
        api: api,
        session: sessions,
        favorites: store,
        vault: vault,
        rememberPassword: () => false,
      );

      await sessions.writeSession(
        const AccountSession(uid: 42, username: 'tester', state: SessionState.valid),
      );
      await sessions.writeCookies(<String, String>{'AVS': 'expired'});

      final restored = await repository.restore();
      expect(restored.state, SessionState.needsLogin);
      expect(api.loginCalls, 0);
    });

    test('登出会清掉保存的密码，避免下次被自动登回去', () async {
      final vault = MemoryCredentialVault();
      await vault.save(
        const SavedCredential(username: 'tester', password: 'pw123456'),
      );
      final api = FakeJmApi(loggedIn: true);
      final repository = AuthRepository(
        api: api,
        session: sessions,
        favorites: store,
        vault: vault,
      );
      await sessions.writeSession(
        const AccountSession(uid: 42, username: 'tester', state: SessionState.valid),
      );

      await repository.logout();

      expect(await vault.read(), isNull);
    });

    test('登出：清会话与 cookie，收藏降级为仅本地', () async {
      final api = FakeJmApi(loggedIn: true);
      final repository = AuthRepository(api: api, session: sessions, favorites: store);
      await sessions.writeSession(
        const AccountSession(uid: 42, username: 'tester', state: SessionState.valid),
      );
      await store.addFromSummary(summary1, sync: FavoriteSyncState.synced);

      await repository.logout();

      expect(sessions.readSession().uid, 0);
      expect(sessions.readCookies(), isEmpty);
      expect(store.contains('1'), isTrue, reason: '本地收藏保留');
      expect(store.item('1')!.sync, FavoriteSyncState.localOnly);
    });
  });
}
