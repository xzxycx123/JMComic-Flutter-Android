import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/icons/app_icons.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/app_typography.dart';
import '../../data/models/account_session.dart';
import '../../data/repositories/favorites_repository.dart';
import '../collect/collect_providers.dart';
import '../collect/favorites_sync.dart';

/// 登录页：用户名 / 密码（ASCII-only），成功后自动做一次收藏双向同步。
class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final TextEditingController _username = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final FocusNode _passwordFocus = FocusNode();
  bool _busy = false;
  bool _syncing = false;
  String? _error;

  static final List<TextInputFormatter> _asciiOnly = <TextInputFormatter>[
    FilteringTextInputFormatter.allow(RegExp(r'[\x20-\x7E]')),
  ];

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final username = _username.text.trim();
    final password = _password.text;
    if (username.isEmpty || password.isEmpty) {
      setState(() => _error = '请输入用户名和密码');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await ref.read(accountSessionProvider.notifier).login(username, password);
    } catch (_) {
      // 原因统一从 provider 里取，下面给出「像样的」提示框。
    }
    if (!mounted) return;

    final async = ref.read(accountSessionProvider);
    final session = async.valueOrNull;
    if (session == null || !session.isLoggedIn) {
      final message = _failureMessage(async);
      setState(() {
        _busy = false;
        _error = message;
      });
      await _showFailureDialog(message);
      return;
    }

    // 登录成功：默认把本地收藏推上云端，同时把云端收藏拉回本地。
    setState(() => _syncing = true);
    final report = await ref.read(favoritesSyncProvider.notifier).syncNow();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _syncing = false;
    });
    await _showSuccessDialog(session, report);
    if (!mounted) return;
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/mine');
    }
  }

  String _failureMessage(AsyncValue<AccountSession> async) {
    final error = async.error;
    if (error == null) return '登录失败，请稍后再试';
    if (error is JmContentException) return error.message;
    if (error is JmApiException) return '网络异常：${error.message}';
    return '$error';
  }

  Future<void> _showFailureDialog(String message) {
    final hint = message.contains('密码') || message.contains('用户名')
        ? '检查一下用户名大小写，密码不要带全角字符。'
        : message.contains('频繁')
            ? '连续失败会触发限流，等 1-2 分钟再试。'
            : '可以在「我的 - 网络」里换一条线路后重试。';
    return showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final scheme = Theme.of(dialogContext).colorScheme;
        return AlertDialog(
          icon: IconTheme(
            data: IconThemeData(color: scheme.error),
            child: const SvgIcon(AppIcons.alert, size: 28),
          ),
          title: const Text('登录失败'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(message, style: AppTypography.body.copyWith(color: scheme.onSurface)),
              const SizedBox(height: 8),
              Text(
                hint,
                style: AppTypography.micro.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('知道了'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                unawaited(_submit());
              },
              child: const Text('重试'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showSuccessDialog(
    AccountSession session,
    FavoriteSyncReport? report,
  ) {
    final syncError = ref.read(favoritesSyncProvider).lastError;
    return showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final scheme = Theme.of(dialogContext).colorScheme;
        return AlertDialog(
          icon: IconTheme(
            data: IconThemeData(color: scheme.primary),
            child: const SvgIcon(AppIcons.check, size: 28),
          ),
          title: Text('已登录：${session.username}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (report == null)
                Text(
                  '登录成功，但收藏同步没有完成${syncError == null ? '' : '：$syncError'}\n'
                  '可以稍后到「我的收藏」右上角手动同步。',
                  style: AppTypography.body.copyWith(color: scheme.onSurface),
                )
              else ...<Widget>[
                Text(
                  '云端 ${report.serverCount} 本 · 拉回 ${report.addedToLocal} 本 · 上传 ${report.pushed} 本',
                  style: AppTypography.body.copyWith(color: scheme.onSurface),
                ),
                if (report.conflicts > 0 || report.failures > 0) ...<Widget>[
                  const SizedBox(height: 6),
                  Text(
                    '${report.conflicts > 0 ? '${report.conflicts} 条冲突已自愈 · ' : ''}'
                    '${report.failures > 0 ? '${report.failures} 条待下次重试' : ''}',
                    style: AppTypography.micro
                        .copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ],
              const SizedBox(height: 10),
              Text(
                '会话保存在本机 cookie 里，密码不会被保存。',
                style: AppTypography.micro.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
          actions: <Widget>[
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('完成'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: '返回',
          icon: IconTheme(
            data: IconThemeData(color: scheme.onSurface),
            child: const SvgIcon(AppIcons.back, size: 22),
          ),
          onPressed: () => context.canPop() ? context.pop() : context.go('/mine'),
        ),
        title: const Text('登录'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
        children: <Widget>[
          Text(
            '登录后会自动把本地收藏同步到云端，并把云端收藏拉回来；密码不会保存在本机。',
            style: AppTypography.caption.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _username,
            autofocus: true,
            enabled: !_busy,
            textInputAction: TextInputAction.next,
            inputFormatters: _asciiOnly,
            autofillHints: const <String>[AutofillHints.username],
            decoration: const InputDecoration(labelText: '用户名'),
            onSubmitted: (_) => _passwordFocus.requestFocus(),
            onTapOutside: (_) => FocusScope.of(context).unfocus(),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _password,
            focusNode: _passwordFocus,
            enabled: !_busy,
            obscureText: true,
            textInputAction: TextInputAction.done,
            inputFormatters: _asciiOnly,
            autofillHints: const <String>[AutofillHints.password],
            decoration: const InputDecoration(labelText: '密码'),
            onSubmitted: (_) => _submit(),
          ),
          if (_error != null) ...<Widget>[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: AppTypography.caption.copyWith(color: scheme.error),
            ),
          ],
          const SizedBox(height: 22),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: _busy
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2.2),
                      ),
                      const SizedBox(width: 10),
                      Text(_syncing ? '正在同步收藏…' : '登录中…'),
                    ],
                  )
                : const Text('登录'),
          ),
          const SizedBox(height: 14),
          Text(
            '账号与收藏接口由站点提供；本客户端只保存会话 cookie，不保存密码。',
            style: AppTypography.micro.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
