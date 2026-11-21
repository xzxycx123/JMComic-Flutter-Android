import 'package:flutter/widgets.dart';

import '../../data/local/settings_store.dart';

/// Material selection lives above the Navigator and its Overlay.
class InterfaceStyleScope extends InheritedWidget {
  const InterfaceStyleScope({
    required this.style,
    required super.child,
    super.key,
  });

  final AppInterfaceStyle style;

  static AppInterfaceStyle of(BuildContext context) => maybeOf(context);

  static AppInterfaceStyle maybeOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<InterfaceStyleScope>()
          ?.style ??
      AppInterfaceStyle.metal;

  @override
  bool updateShouldNotify(InterfaceStyleScope oldWidget) =>
      style != oldWidget.style;
}

extension InterfaceStyleContext on BuildContext {
  AppInterfaceStyle get interfaceStyle => InterfaceStyleScope.of(this);
  bool get isLiquidGlass => interfaceStyle == AppInterfaceStyle.liquidGlass;
}
