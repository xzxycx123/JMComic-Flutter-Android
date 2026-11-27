import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:jm_comic/core/network/api_exception.dart';
import 'package:jm_comic/core/theme/app_glass_theme.dart';
import 'package:jm_comic/core/theme/interface_style_scope.dart';
import 'package:jm_comic/core/ui/glass/app_button.dart';
import 'package:jm_comic/data/local/settings_store.dart';
import 'package:jm_comic/data/models/account_session.dart';
import 'package:jm_comic/data/repositories/favorites_repository.dart';
import 'package:jm_comic/features/auth/login_page.dart';
import 'package:jm_comic/features/collect/collect_providers.dart';
import 'package:jm_comic/features/collect/favorites_sync.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

class _TestSettings extends SettingsNotifier {
  @override
  AppSettings build() => const AppSettings();
}

class _TestSession extends AccountSessionNotifier {
  var attempts = 0;

  @override
  Future<AccountSession> build() async => AccountSession.local;

  @override
  Future<void> login(String username, String password, {bool? remember}) async {
    attempts++;
    if (attempts == 1) {
      state = AsyncError(const JmContentException('密码不正确'), StackTrace.current);
      return;
    }
    state = AsyncData(
      AccountSession(uid: 1, username: username, state: SessionState.valid),
    );
  }
}

class _TestFavoritesSync extends FavoritesSyncNotifier {
  @override
  Future<FavoriteSyncReport?> syncNow() async => const FavoriteSyncReport();
}

void main() {
  for (final style in AppInterfaceStyle.values) {
    testWidgets('$style 登录校验、失败及成功弹窗', (tester) async {
      final session = _TestSession();
      final router = GoRouter(
        initialLocation: '/login',
        routes: [
          GoRoute(path: '/login', builder: (_, __) => const LoginPage()),
          GoRoute(
            path: '/mine',
            builder: (_, __) => const Scaffold(body: Text('我的')),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsProvider.overrideWith(_TestSettings.new),
            accountSessionProvider.overrideWith(() => session),
            favoritesSyncProvider.overrideWith(_TestFavoritesSync.new),
          ],
          child: LiquidGlassWidgets.wrap(
            theme: AppGlassTheme.preset,
            brightnessResolver: Theme.maybeBrightnessOf,
            child: MaterialApp.router(
              routerConfig: router,
              builder: (_, child) =>
                  InterfaceStyleScope(style: style, child: child!),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(LoginPage)),
        listen: false,
      );
      await container.read(accountSessionProvider.future);

      final glass = style == AppInterfaceStyle.liquidGlass;
      void expectDialog(String title) {
        expect(find.text(title), findsOneWidget);
        final dialog = find.byType(glass ? GlassDialog : AlertDialog);
        expect(dialog, findsOneWidget);
        if (glass) {
          expect(tester.widget<GlassDialog>(dialog).settings, isNull);
        }
      }

      final login = find.widgetWithText(AppButton, '登录');
      await tester.tap(login);
      await tester.pumpAndSettle();
      expectDialog('请填写登录信息');
      expect(session.attempts, 0);
      await tester.tap(find.text('知道了'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(EditableText).at(0), 'tester');
      await tester.enterText(find.byType(EditableText).at(1), 'password');
      await tester.tap(login);
      await tester.pumpAndSettle();
      expectDialog('登录失败');
      expect(find.text('密码不正确'), findsOneWidget);

      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();
      expectDialog('已登录：tester');
      expect(session.attempts, 2);
      await tester.tap(find.text('完成'));
      await tester.pumpAndSettle();
      expect(find.text('我的'), findsOneWidget);
    });
  }
}
