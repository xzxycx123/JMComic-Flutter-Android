import 'dart:async';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../../../core/utils/logger.dart';

/// 前台服务 + 通知进度（`flutter_foreground_task`）。
///
/// 只做两件事：保活进程、把当前任务摘要写进通知。
/// 所有调用都做降级处理：插件不可用（桌面 / 单测）时静默失败，下载照常进行。
class DownloadNotificationService {
  DownloadNotificationService({this.enabled = true});

  static const String channelId = 'jm_downloads';
  static const String channelName = '漫画下载';
  static const int serviceId = 2000;

  final bool enabled;

  bool _initialized = false;
  bool _running = false;

  Future<void> ensureStarted({String title = 'JMComic', String text = '下载准备中'}) async {
    if (!enabled) return;
    try {
      if (!_initialized) {
        FlutterForegroundTask.init(
          androidNotificationOptions: AndroidNotificationOptions(
            channelId: channelId,
            channelName: channelName,
            channelDescription: '显示漫画下载与 PDF 导出进度',
            onlyAlertOnce: true,
          ),
          iosNotificationOptions: const IOSNotificationOptions(
            showNotification: false,
            playSound: false,
          ),
          foregroundTaskOptions: ForegroundTaskOptions(
            eventAction: ForegroundTaskEventAction.nothing(),
            autoRunOnBoot: false,
            autoRunOnMyPackageReplaced: false,
            allowWakeLock: true,
            allowWifiLock: true,
          ),
        );
        _initialized = true;
      }

      final permission = await FlutterForegroundTask.checkNotificationPermission();
      if (permission != NotificationPermission.granted) {
        await FlutterForegroundTask.requestNotificationPermission();
      }

      if (await FlutterForegroundTask.isRunningService) {
        _running = true;
        await update(title: title, text: text);
        return;
      }

      await FlutterForegroundTask.startService(
        serviceId: serviceId,
        notificationTitle: title,
        notificationText: text,
        callback: downloadTaskCallback,
      );
      _running = true;
    } catch (error) {
      Log.w('前台服务启动失败（下载继续）：$error');
    }
  }

  Future<void> update({required String title, required String text}) async {
    if (!enabled || !_running) return;
    try {
      await FlutterForegroundTask.updateService(
        notificationTitle: title,
        notificationText: text,
      );
    } catch (error) {
      Log.w('通知更新失败：$error');
    }
  }

  Future<void> stop() async {
    if (!enabled || !_running) return;
    try {
      await FlutterForegroundTask.stopService();
    } catch (error) {
      Log.w('前台服务停止失败：$error');
    }
    _running = false;
  }
}

/// 前台服务回调必须是顶层函数。
@pragma('vm:entry-point')
void downloadTaskCallback() {
  FlutterForegroundTask.setTaskHandler(_DownloadTaskHandler());
}

class _DownloadTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    Log.i('前台服务启动');
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    // 下载进度由主 isolate 主动 updateService，这里不需要轮询。
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {
    Log.i('前台服务结束');
  }
}
