import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../../data/local/settings_store.dart';
import 'glass_nav_bar.dart';

/// 两 tab 外壳：StatefulShellRoute 保留分支栈，并按设置切换 Dock 材质。
class ShellPage extends ConsumerWidget {
  const ShellPage({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void selectBranch(int index) {
      navigationShell.goBranch(
        index,
        initialLocation: index == navigationShell.currentIndex,
      );
    }

    if (ref.watch(interfaceStyleProvider) == AppInterfaceStyle.liquidGlass) {
      final scheme = Theme.of(context).colorScheme;
      return GlassScaffold(
        extendBody: true,
        backgroundColor: scheme.surface,
        background: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[
                Color.lerp(scheme.surface, scheme.primaryContainer, 0.45)!,
                scheme.surface,
                Color.lerp(scheme.surface, scheme.secondary, 0.08)!,
              ],
              stops: const <double>[0, 0.48, 1],
            ),
          ),
        ),
        statusBarStyle: GlassStatusBarStyle.auto,
        body: navigationShell,
        bottomBar: LiquidGlassNavBar(
          currentIndex: navigationShell.currentIndex,
          onSelect: selectBranch,
        ),
      );
    }

    return Scaffold(
      extendBody: true,
      body: navigationShell,
      bottomNavigationBar: GlassNavBar(
        currentIndex: navigationShell.currentIndex,
        onSelect: selectBranch,
      ),
    );
  }
}
