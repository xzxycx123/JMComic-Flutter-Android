import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../../core/theme/interface_style_scope.dart';
import '../../core/ui/glass/app_glass_page.dart';
import '../update/update_gate.dart';
import 'glass_nav_bar.dart';

/// 两 tab 外壳：StatefulShellRoute 保留分支栈，并按设置切换 Dock 材质。
class ShellPage extends StatefulWidget {
  const ShellPage({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  @override
  State<ShellPage> createState() => _ShellPageState();
}

class _ShellPageState extends State<ShellPage> {
  // The glass shell and Metal Scaffold lay out their bodies differently.
  // Reparent the navigator subtree instead of disposing the branch pages.
  final GlobalKey _bodyKey = GlobalKey();

  /// 设置页是「我的」分支里的二级页（返回靠 AppBar），底部 Dock 在那儿只挡内容：
  /// 命中这些路径就收起 Dock，返回即恢复。
  static bool _hidesDock(String path) => path == '/mine/settings';

  @override
  Widget build(BuildContext context) {
    final navigationShell = widget.navigationShell;
    // 启动即检查新版本（开关在设置页，检查结果进 updateCheckProvider）。
    final body = UpdateGate(
      child: KeyedSubtree(key: _bodyKey, child: navigationShell),
    );
    void selectBranch(int index) {
      navigationShell.goBranch(
        index,
        initialLocation: index == navigationShell.currentIndex,
      );
    }

    // 分支内的二级页切换不会重建 ShellPage，这里直接盯 delegate，跳转即重算。
    final router = GoRouter.of(context);
    return AnimatedBuilder(
      animation: router.routerDelegate,
      builder: (context, _) {
        final hideDock = _hidesDock(
          router.routerDelegate.currentConfiguration.uri.path,
        );

        if (context.isLiquidGlass) {
          return GlassScaffold(
            extendBody: true,
            backgroundColor: Theme.of(context).colorScheme.surface,
            background: const AppGlassBackground(),
            statusBarStyle: GlassStatusBarStyle.auto,
            body: body,
            bottomBar: hideDock
                ? null
                : LiquidGlassNavBar(
                    currentIndex: navigationShell.currentIndex,
                    onSelect: selectBranch,
                  ),
          );
        }

        return Scaffold(
          extendBody: true,
          body: body,
          bottomNavigationBar: hideDock
              ? null
              : GlassNavBar(
                  currentIndex: navigationShell.currentIndex,
                  onSelect: selectBranch,
                ),
        );
      },
    );
  }
}
