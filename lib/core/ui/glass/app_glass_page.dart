import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_glass_theme.dart';
import '../../theme/interface_style_scope.dart';

/// Keeps a single Scaffold and the same body subtree across material changes.
class AppGlassPage extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final glass = context.isLiquidGlass;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (glass && showBackground)
          const Positioned.fill(child: AppGlassBackground()),
        Scaffold(
          appBar: appBar,
          backgroundColor: glass ? Colors.transparent : backgroundColor,
          extendBody: extendBody,
          extendBodyBehindAppBar: extendBodyBehindAppBar,
          resizeToAvoidBottomInset: resizeToAvoidBottomInset,
          bottomNavigationBar: bottomNavigationBar == null
              ? null
              : GlassBackdropGroup(
                  enabled: glass,
                  child: bottomNavigationBar!,
                ),
          body: body,
        ),
      ],
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
    final glass = context.isLiquidGlass;
    return GlassBackdropGroup(
      enabled: glass,
      child: AppBar(
        title: title,
        leading: leading,
        actions: actions,
        titleSpacing: titleSpacing,
        centerTitle: centerTitle,
        toolbarHeight: toolbarHeight,
        backgroundColor: glass ? Colors.transparent : null,
        surfaceTintColor: glass ? Colors.transparent : null,
        automaticallyImplyLeading: !glass,
        flexibleSpace:
            glass ? const AppGlassChrome(child: SizedBox.expand()) : null,
      ),
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
