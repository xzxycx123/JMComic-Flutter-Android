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

    if (context.isLiquidGlass) {
      return GlassScaffold(
        extendBody: true,
        backgroundColor: Theme.of(context).colorScheme.surface,
        background: const AppGlassBackground(),
        statusBarStyle: GlassStatusBarStyle.auto,
        body: body,
        bottomBar: LiquidGlassNavBar(
          currentIndex: navigationShell.currentIndex,
          onSelect: selectBranch,
        ),
      );
    }

    return Scaffold(
      extendBody: true,
      body: body,
      bottomNavigationBar: GlassNavBar(
        currentIndex: navigationShell.currentIndex,
        onSelect: selectBranch,
      ),
    );
  }
}
