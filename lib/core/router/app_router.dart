import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/album/album_page.dart';
import '../../features/download/download_page.dart';
import '../../features/home/home_page.dart';
import '../../features/mine/about_page.dart';
import '../../features/mine/mine_page.dart';
import '../../features/mine/settings_page.dart';
import '../../features/reader/reader_mode.dart';
import '../../features/reader/reader_page.dart';
import '../../features/search/search_page.dart';
import '../../features/shell/shell_page.dart';

/// 全局路由表（三 tab 壳 + 顶层详情 / 搜索 / 阅读器）。
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
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/download',
                builder: (context, state) => const DownloadPage(),
              ),
            ],
          ),
        ],
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
