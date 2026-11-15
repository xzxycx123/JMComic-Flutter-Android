import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/album/album_page.dart';
import '../../features/auth/login_page.dart';
import '../../features/collect/collect_page.dart';
import '../../features/download/download_page.dart';
import '../../features/download/history_page.dart';
import '../../features/home/home_page.dart';
import '../../features/mine/about_page.dart';
import '../../features/mine/mine_page.dart';
import '../../features/mine/settings_page.dart';
import '../../features/reader/reader_mode.dart';
import '../../features/reader/reader_page.dart';
import '../../features/search/search_page.dart';
import '../../features/shell/shell_page.dart';

/// 全局路由表：两 tab 壳（首页 / 我的）+ 顶层详情 / 搜索 / 阅读器 / 下载 / 历史。
///
/// 下载与历史不再是 dock 的一档，改从「我的」的二级菜单进入（push 到顶层，返回即回我的）。
final Provider<GoRouter> goRouterProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    initialLocation: '/',
    routes: <RouteBase>[
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            ShellPage(navigationShell: navigationShell),
        branches: <StatefulShellBranch>[
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/',
                builder: (context, state) => const HomePage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/mine',
                builder: (context, state) => const MinePage(),
                routes: <RouteBase>[
                  GoRoute(
                    path: 'settings',
                    builder: (context, state) => const SettingsPage(),
                  ),
                  GoRoute(
                    path: 'about',
                    builder: (context, state) => const AboutPage(),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/download',
        builder: (context, state) => const DownloadPage(),
      ),
      GoRoute(
        path: '/history',
        builder: (context, state) => const HistoryPage(),
      ),
      GoRoute(
        path: '/collect',
        builder: (context, state) => const CollectPage(),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginPage(),
      ),
      GoRoute(
        path: '/search',
        builder: (context, state) => const SearchPage(),
      ),
      GoRoute(
        path: '/album/:albumId',
        builder: (context, state) => AlbumPage(
          albumId: state.pathParameters['albumId'] ?? '',
        ),
      ),
      GoRoute(
        path: '/reader',
        builder: (context, state) => ReaderPage(
          args: ReaderArgs.fromQuery(state.uri.queryParameters),
        ),
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});
