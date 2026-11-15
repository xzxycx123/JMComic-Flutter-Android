import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/config/app_config.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'data/local/settings_store.dart';
import 'features/collect/collect_providers.dart';

/// 根 widget：主题 + 路由。
class JmComicApp extends ConsumerWidget {
  const JmComicApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(goRouterProvider);
    final themeMode = ref.watch(themeModeProvider);

    // 启动即恢复会话：cookie 失效时顺带用保存的密码自动重登，
    // 别等用户点进「我的」才去校验（那时点赞/评论已经因为未登录被拦了）。
    ref.read(accountSessionProvider);

    return MaterialApp.router(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      routerConfig: router,
    );
  }
}
