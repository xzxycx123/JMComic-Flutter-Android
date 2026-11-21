import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_glass_theme.dart';
import '../../theme/interface_style_scope.dart';

/// Keeps the same body subtree while choosing the platform chrome.
class AppGlassPage extends StatefulWidget {
  const AppGlassPage({
    super.key,
    required this.body,
    this.appBar,
    this.backgroundColor,
    this.showBackground = true,
    this.bottomNavigationBar,
    this.extendBody = false,
    this.extendBodyBehindAppBar = false,
    this.resizeToAvoidBottomInset,
  });

  final Widget body;
  final PreferredSizeWidget? appBar;
  final Color? backgroundColor;
  final bool showBackground;
  final Widget? bottomNavigationBar;
  final bool extendBody;
  final bool extendBodyBehindAppBar;
  final bool? resizeToAvoidBottomInset;

  @override
  State<AppGlassPage> createState() => _AppGlassPageState();
}

class _AppGlassPageState extends State<AppGlassPage> {
  final GlobalKey _bodyKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final body = KeyedSubtree(key: _bodyKey, child: widget.body);
    if (context.isLiquidGlass) {
      final hasBottomBar = widget.bottomNavigationBar != null;
      if (!widget.showBackground && widget.appBar == null && !hasBottomBar) {
        return Material(type: MaterialType.transparency, child: body);
      }
      return GlassScaffold(
        body: Material(type: MaterialType.transparency, child: body),
        appBar: widget.appBar,
        bottomBar: hasBottomBar
            ? GlassBackdropGroup(child: widget.bottomNavigationBar!)
            : null,
        bottomBarHeight: hasBottomBar ? 68 : null,
        background: widget.showBackground ? const AppGlassBackground() : null,
        backgroundColor: widget.showBackground
            ? Theme.of(context).colorScheme.surface
            : Colors.transparent,
        enableBackgroundSampling: false,
        statusBarStyle: GlassStatusBarStyle.auto,
        resizeToAvoidBottomInset: widget.resizeToAvoidBottomInset,
        extendBody: widget.extendBody || widget.extendBodyBehindAppBar,
      );
    }
    return Scaffold(
      appBar: widget.appBar,
      backgroundColor: widget.backgroundColor,
      extendBody: widget.extendBody,
      extendBodyBehindAppBar: widget.extendBodyBehindAppBar,
      resizeToAvoidBottomInset: widget.resizeToAvoidBottomInset,
      bottomNavigationBar: widget.bottomNavigationBar,
      body: body,
    );
  }
}

class AppGlassBackground extends StatelessWidget {
  const AppGlassBackground({super.key});

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration:
            BoxDecoration(gradient: AppGlassTheme.of(context).background),
      );
}

/// Standard secondary-page chrome. Retains the original Material bar geometry.
class AppGlassAppBar extends StatelessWidget implements PreferredSizeWidget {
  const AppGlassAppBar({
    super.key,
    this.title,
    this.leading,
    this.actions,
    this.titleSpacing,
    this.centerTitle,
    this.toolbarHeight = kToolbarHeight,
  });

  final Widget? title;
  final Widget? leading;
  final List<Widget>? actions;
  final double? titleSpacing;
  final bool? centerTitle;
  final double toolbarHeight;

  @override
  Size get preferredSize => Size.fromHeight(toolbarHeight);

  @override
  Widget build(BuildContext context) {
    if (context.isLiquidGlass) {
      return DefaultTextStyle.merge(
        style:
            Theme.of(context).appBarTheme.titleTextStyle ?? const TextStyle(),
        child: GlassAppBar(
          title: title,
          leading: leading,
          actions: actions,
          centerTitle: centerTitle ?? false,
          toolbarHeight: toolbarHeight,
        ),
      );
    }
    return AppBar(
      title: title,
      leading: leading,
      actions: actions,
      titleSpacing: titleSpacing,
      centerTitle: centerTitle,
      toolbarHeight: toolbarHeight,
    );
  }
}

/// A pinned toolbar scrim. Its content is a sibling of the glass surface, so
/// button lenses never sit inside a refractive parent. Reader chrome uses no
/// backdrop read, leaving the pixels of the original pages untouched.
class AppGlassChrome extends StatelessWidget {
  const AppGlassChrome({
    super.key,
    required this.child,
    this.reader = false,
    this.metalColor,
  });

  final Widget child;
  final bool reader;
  final Color? metalColor;

  @override
  Widget build(BuildContext context) {
    final glass = context.isLiquidGlass;
    final theme = AppGlassTheme.of(context, reader: reader);
    return Stack(
      children: [
        if (glass)
          Positioned.fill(
            child: IgnorePointer(
              child: reader
                  ? DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            theme.scheme.surfaceContainerHigh
                                .withValues(alpha: .94),
                            AppColors.readerBg.withValues(alpha: .94),
                          ],
                        ),
                        border: Border.symmetric(
                          horizontal: BorderSide(
                            color: theme.outline.withValues(alpha: .6),
                          ),
                        ),
                      ),
                    )
                  : AdaptiveGlass(
                      shape: const LiquidRoundedRectangle(borderRadius: 0),
                      settings: theme.chrome,
                      quality: GlassQuality.minimal,
                      useOwnLayer: false,
                      child: const SizedBox.expand(),
                    ),
            ),
          )
        else if (metalColor != null)
          Positioned.fill(
            child: IgnorePointer(child: ColoredBox(color: metalColor!)),
          ),
        child,
      ],
    );
  }
}
