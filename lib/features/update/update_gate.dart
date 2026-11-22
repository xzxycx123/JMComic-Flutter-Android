import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local/settings_store.dart';
import 'update_dialog.dart';
import 'update_providers.dart';

/// 启动检查：首帧之后跑一次「有没有新版本」，有就弹「检测到新版本」。
///
/// 放在 shell 里（而不是 `MaterialApp.builder`），因为弹窗需要 Navigator；
/// 是否已经查过由 [UpdateCheckNotifier] 自己记住，重建 / 切皮肤不会重复弹。
class UpdateGate extends ConsumerStatefulWidget {
  const UpdateGate({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<UpdateGate> createState() => _UpdateGateState();
}

class _UpdateGateState extends ConsumerState<UpdateGate> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkOnStartup());
  }

  Future<void> _checkOnStartup() async {
    if (!mounted) return;
    if (!ref.read(settingsProvider).autoUpdateCheck) return;

    final state = await ref.read(updateCheckProvider.notifier).autoCheck();
    if (!mounted || state == null) return;
    final release = state.release;
    if (release == null) return;
    // 「跳过此版本」只压住这一个 tag，更新版本出现时照常提醒。
    if (ref.read(settingsProvider).skippedReleaseTag == release.tag) return;

    await promptForRelease(
      context: context,
      ref: ref,
      release: release,
      current: state.currentVersion,
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
