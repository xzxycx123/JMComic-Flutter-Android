import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/icons/app_icons.dart';
import '../../core/theme/app_typography.dart';
import '../collect/collect_providers.dart';

/// 登录页：用户名 / 密码（ASCII-only），成功后回到上一页。
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
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final notifier = ref.read(accountSessionProvider.notifier);
      await notifier.login(username, password);
      final session = ref.read(accountSessionProvider).valueOrNull;
      if (session == null || !session.isLoggedIn) {
        final error = ref.read(accountSessionProvider).error;
        setState(() => _error = error?.toString() ?? '登录失败，请稍后重试');
        return;
      }
      if (!mounted) return;
      FocusScope.of(context).unfocus();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已登录：${session.username}')),
      );
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/mine');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
            '登录后可把本地收藏同步到账号；密码不会保存在本机。',
            style: AppTypography.caption.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _username,
            autofocus: true,
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
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.2),
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
