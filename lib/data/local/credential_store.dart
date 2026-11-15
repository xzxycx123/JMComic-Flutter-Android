import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/utils/logger.dart';

/// 已保存的登录凭据（只在用户开启「记住密码」时存在）。
class SavedCredential {
  const SavedCredential({required this.username, required this.password});

  final String username;
  final String password;

  bool get isValid => username.trim().isNotEmpty && password.isNotEmpty;
}

/// 凭据仓库抽象：登录页/仓储只依赖它，测试可注入内存实现。
abstract class CredentialVault {
  Future<SavedCredential?> read();

  Future<void> save(SavedCredential credential);

  Future<void> clear();
}

/// 系统密钥库实现（Android Keystore / iOS Keychain）。
///
/// 用途只有一个：cookie 失效时自动重登一次（对齐 jm-mobile 的自动登录，但落盘位置从
/// 明文换成系统密钥库）。任何平台异常都降级为「没有保存过」，不影响登录主流程。
class SecureCredentialVault implements CredentialVault {
  SecureCredentialVault([FlutterSecureStorage? storage])
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  static const String _keyUsername = 'jm_login_username';
  static const String _keyPassword = 'jm_login_password';

  final FlutterSecureStorage _storage;

  @override
  Future<SavedCredential?> read() async {
    try {
      final username = await _storage.read(key: _keyUsername);
      final password = await _storage.read(key: _keyPassword);
      if (username == null || password == null) return null;
      final credential =
          SavedCredential(username: username, password: password);
      return credential.isValid ? credential : null;
    } catch (error) {
      Log.w('读取已保存凭据失败（按未保存处理）：$error');
      return null;
    }
  }

  @override
  Future<void> save(SavedCredential credential) async {
    if (!credential.isValid) return;
    try {
      await _storage.write(key: _keyUsername, value: credential.username);
      await _storage.write(key: _keyPassword, value: credential.password);
    } catch (error) {
      Log.w('保存凭据失败（下次仍需手动登录）：$error');
    }
  }

  @override
  Future<void> clear() async {
    try {
      await _storage.delete(key: _keyUsername);
      await _storage.delete(key: _keyPassword);
    } catch (error) {
      Log.w('清除已保存凭据失败：$error');
    }
  }
}

/// 内存实现（测试 / 无法使用密钥库时的兜底）。
class MemoryCredentialVault implements CredentialVault {
  SavedCredential? _credential;

  @override
  Future<SavedCredential?> read() async => _credential;

  @override
  Future<void> save(SavedCredential credential) async {
    _credential = credential.isValid ? credential : null;
  }

  @override
  Future<void> clear() async => _credential = null;
}
