import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../ui/app_toast.dart';

class AppExitGuard extends StatefulWidget {
  const AppExitGuard({required this.child, super.key});

  final Widget child;

  @override
  State<AppExitGuard> createState() => _AppExitGuardState();
}

class _AppExitGuardState extends State<AppExitGuard> {
  static const _confirmationWindow = Duration(seconds: 2);

  Timer? _confirmationTimer;

  @override
  void dispose() {
    _confirmationTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return widget.child;
    }

    final wouldExit = ModalRoute.canPopOf(context) == false &&
        ModalRoute.isCurrentOf(context) == true;
    if (!wouldExit) _confirmationTimer?.cancel();

    return PopScope<Object?>(
      canPop: !wouldExit,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || !wouldExit) return;

        if (_confirmationTimer?.isActive ?? false) {
          _confirmationTimer?.cancel();
          AppToast.dismiss();
          unawaited(SystemNavigator.pop());
          return;
        }

        _confirmationTimer = Timer(_confirmationWindow, () {
          _confirmationTimer = null;
        });
        AppToast.show(context, '再滑一次退出', duration: _confirmationWindow);
      },
      child: widget.child,
    );
  }
}
