import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/icons/app_icons.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/app_typography.dart';
import '../../core/ui/glass/app_glass.dart';
import '../../data/local/settings_store.dart';
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
  bool _showPassword = false;
  bool? _remember;
  String? _error;

  static final List<TextInputFormatter> _asciiOnly = <TextInputFormatter>[
    FilteringTextInputFormatter.allow(RegExp(r'[\x20-\x7E]')),
  ];

  bool get _rememberPassword =>
      _remember ?? ref.read(settingsProvider).rememberPassword;

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
      await ref.read(accountSessionProvider.notifier).login(
            username,
            password,
            remember: _rememberPassword,
          );
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

  Future<void> _showFailureDialog(String message) async {
    final hint = message.contains('密码') || message.contains('用户名')
        ? '检查一下用户名大小写，密码不要带全角字符。'
        : message.contains('频繁')
            ? '连续失败会触发限流，等 1-2 分钟再试。'
            : '可以在「我的 - 网络」里换一条线路后重试。';
    final retry = await AppDialog.show<bool>(
      context: context,
      title: '登录失败',
      iconBuilder: (dialogContext) => SvgIcon(
        AppIcons.alert,
        color: Theme.of(dialogContext).colorScheme.error,
        size: 28,
      ),
      contentBuilder: (dialogContext) {
        final scheme = Theme.of(dialogContext).colorScheme;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              message,
              style: AppTypography.body.copyWith(color: scheme.onSurface),
            ),
            const SizedBox(height: 8),
            Text(
              hint,
              style:
                  AppTypography.micro.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        );
      },
      actions: const <AppDialogAction<bool>>[
        AppDialogAction(label: '知道了'),
        AppDialogAction(label: '重试', result: true, primary: true),
      ],
    );
    if (retry == true && mounted) unawaited(_submit());
  }

  Future<void> _showSuccessDialog(
    AccountSession session,
    FavoriteSyncReport? report,
  ) {
    final syncError = ref.read(favoritesSyncProvider).lastError;
    return AppDialog.show<void>(
      context: context,
      title: '已登录：${session.username}',
      iconBuilder: (dialogContext) => SvgIcon(
        AppIcons.check,
        color: Theme.of(dialogContext).colorScheme.primary,
        size: 28,
      ),
      contentBuilder: (dialogContext) {
        final scheme = Theme.of(dialogContext).colorScheme;
        return Column(
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
              '会话保存在本机 cookie 里；开启「记住密码」时密码在系统密钥库，用于 cookie 失效后自动重登。',
              style:
                  AppTypography.micro.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        );
      },
      actions: const <AppDialogAction<void>>[
        AppDialogAction(label: '完成', primary: true),
      ],
    );
  }

  Future<void> _setRememberPassword(bool value) async {
    setState(() => _remember = value);
    final auth = value ? null : ref.read(authRepositoryProvider);
    await ref.read(settingsProvider.notifier).setRememberPassword(value);
    await auth?.forgetPassword();
  }

  Widget _rememberTile(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final value = _rememberPassword;
    final title = Text(
      '记住密码（cookie 失效时自动重登）',
      style: AppTypography.body.copyWith(color: scheme.onSurface),
    );
    final subtitle = Text(
      '账号密码存进系统密钥库（Android Keystore），退出 App 也不会掉登录。',
      style: AppTypography.micro.copyWith(color: scheme.onSurfaceVariant),
    );
    final onChanged = _busy ? null : _setRememberPassword;
    if (!context.isLiquidGlass) {
      return SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        value: value,
        onChanged: onChanged,
        title: title,
        subtitle: subtitle,
      );
    }
    return AppSurface(
      kind: AppSurfaceKind.controlGroup,
      child: AppListTile(
        title: title,
        subtitle: subtitle,
        enabled: !_busy,
        trailing: AppSwitch.adaptive(value: value, onChanged: onChanged),
        onTap: onChanged == null ? null : () => onChanged(!value),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AppGlassPage(
      appBar: AppGlassAppBar(
        leading: AppIconButton(
          tooltip: '返回',
          icon: IconTheme(
            data: IconThemeData(color: scheme.onSurface),
            child: const SvgIcon(AppIcons.back, size: 22),
          ),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/mine'),
        ),
        title: const Text('登录'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
        children: <Widget>[
          Text(
            '登录后会自动把本地收藏同步到云端，并把云端收藏拉回来；勾选「记住密码」后，cookie 失效时会用密钥库里的密码自动重登。',
            style:
                AppTypography.caption.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 20),
          AppTextField(
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
          AppTextField(
            controller: _password,
            focusNode: _passwordFocus,
            enabled: !_busy,
            obscureText: !context.isLiquidGlass || !_showPassword,
            textInputAction: TextInputAction.done,
            inputFormatters: _asciiOnly,
            autofillHints: const <String>[AutofillHints.password],
            decoration: InputDecoration(
              labelText: '密码',
              suffixIcon: context.isLiquidGlass
                  ? AppIconButton(
                      glassTransparent: true,
                      tooltip: _showPassword ? '隐藏密码' : '显示密码',
                      onPressed: _busy
                          ? null
                          : () =>
                              setState(() => _showPassword = !_showPassword),
                      icon: SvgIcon(
                        _showPassword ? AppIcons.eyeOff : AppIcons.eye,
                        size: 19,
                      ),
                    )
                  : null,
            ),
            onSubmitted: (_) => _submit(),
          ),
          if (_error != null) ...<Widget>[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: AppTypography.caption.copyWith(color: scheme.error),
            ),
          ],
          const SizedBox(height: 8),
          _rememberTile(context),
          const SizedBox(height: 14),
          AppButton(
            onPressed: _busy ? null : _submit,
            loading: context.isLiquidGlass && _busy,
            label: _busy ? (_syncing ? '正在同步收藏…' : '登录中…') : '登录',
            child: _busy && !context.isLiquidGlass
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: AppProgressIndicator.circular(strokeWidth: 2.2),
                      ),
                      const SizedBox(width: 10),
                      Text(_syncing ? '正在同步收藏…' : '登录中…'),
                    ],
                  )
                : null,
          ),
          const SizedBox(height: 14),
          Text(
            '账号与收藏接口由站点提供；密码只在开启「记住密码」时存进系统密钥库，可随时在设置里清除。',
            style: AppTypography.micro.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
