import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/providers.dart';
import '../../data/models/app_version.dart';
import '../../data/models/release_info.dart';
import '../../data/local/settings_store.dart';
import '../../data/repositories/update_repository.dart';

/// 一次检查的结果形态。
enum UpdatePhase { idle, checking, upToDate, available, failed }

/// 「有没有新版本」的快照：设置页 / 我的页 / 启动弹窗共用一份。
class UpdateCheckState {
  const UpdateCheckState({
    this.phase = UpdatePhase.idle,
    this.release,
    this.currentVersion = AppVersion.unknown,
    this.message = '',
  });

  final UpdatePhase phase;

  /// 有新版时非 null（跳过过也仍然是这个版本）。
  final ReleaseInfo? release;
  final AppVersion currentVersion;
  final String message;

  bool get hasUpdate => release != null;

  bool get checking => phase == UpdatePhase.checking;

  /// 设置行右侧的文案。
  String get summary {
    switch (phase) {
      case UpdatePhase.idle:
        return '点此检查';
      case UpdatePhase.checking:
        return '检查中…';
      case UpdatePhase.available:
        return '发现 ${release?.versionLabel ?? '新版本'}';
      case UpdatePhase.upToDate:
        return '已是最新';
      case UpdatePhase.failed:
        return '检查失败';
    }
  }

  UpdateCheckState copyWith({
    UpdatePhase? phase,
    ReleaseInfo? release,
    AppVersion? currentVersion,
    String? message,
    bool clearRelease = false,
  }) =>
      UpdateCheckState(
        phase: phase ?? this.phase,
        release: clearRelease ? null : (release ?? this.release),
        currentVersion: currentVersion ?? this.currentVersion,
        message: message ?? this.message,
      );
}

final NotifierProvider<UpdateCheckNotifier, UpdateCheckState>
    updateCheckProvider =
    NotifierProvider<UpdateCheckNotifier, UpdateCheckState>(
  UpdateCheckNotifier.new,
);

class UpdateCheckNotifier extends Notifier<UpdateCheckState> {
  /// 本次进程是否已经跑过启动检查（切皮肤 / 重建 shell 不会重复弹窗）。
  bool _autoChecked = false;

  @override
  UpdateCheckState build() => UpdateCheckState(
        currentVersion: ref.read(updateRepositoryProvider).installedVersion,
      );

  UpdateRepository get _repository => ref.read(updateRepositoryProvider);

  /// 启动时最多跑一次；返回 null 表示这次没检查（已经查过 / 开关关着）。
  Future<UpdateCheckState?> autoCheck() async {
    if (_autoChecked) return null;
    _autoChecked = true;
    return check();
  }

  /// 手动 / 自动共用的检查入口。失败不抛，落在 [UpdatePhase.failed]。
  Future<UpdateCheckState> check() async {
    if (state.checking) return state;
    final current = await _repository.resolveInstalledVersion();
    state = UpdateCheckState(
      phase: UpdatePhase.checking,
      currentVersion: current,
      release: state.release,
      message: '正在检查新版本…',
    );
    try {
      final release = await _repository.findNewerThan(current);
      state = UpdateCheckState(
        phase: release == null ? UpdatePhase.upToDate : UpdatePhase.available,
        release: release,
        currentVersion: current,
        message: release == null
            ? '已是最新版本 ${current.display}'
            : '发现新版本 ${release.versionLabel}',
      );
    } catch (error) {
      state = UpdateCheckState(
        phase: UpdatePhase.failed,
        currentVersion: current,
        message: _short(error),
      );
    }
    return state;
  }

  /// 错误信息压成一行（设置页 / toast 里只放得下一行）。
  static String _short(Object error) {
    final text = '$error'.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.length <= 140) return text;
    return '${text.substring(0, 140)}...';
  }

  /// 清掉「跳过此版本」的记录（设置页里点一下就能重新被提醒）。
  Future<void> clearSkipped() async {
    await ref.read(settingsProvider.notifier).setSkippedReleaseTag('');
    state = state.copyWith(message: '已取消跳过，下次启动会重新提醒');
  }
}
