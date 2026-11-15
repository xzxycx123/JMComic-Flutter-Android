import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:pointycastle/export.dart';

import '../../core/constants/jm_constants.dart';

/// token / AES-256-ECB 加解密（移植 `JmScript/data/JmCrypto.kt`）。
///
/// 关键点（2026-11-15 实网复核）：
/// - key = `ASCII(md5hex(ts + secret))` 全部 **32 个字节**，即 AES-256；
///   **不是** md5 的 16 个原始字节，也**不能**截断成 16 个字符（截断后 AES-128 解不出明文，
///   表现就是「HTTP 200 但所有线路都解密失败」——旧实现正是踩了这个坑）；
/// - Base64 先按 MIME 容错去空白，再按 4 取模补 `=`；
/// - ECB 单块加解密 + PKCS7 去填充，直接走 [AESEngine]，避免 PaddedBlockCipher 的泛型坑。
abstract final class JmCrypto {
  static String md5Hex(String input) =>
      crypto.md5.convert(utf8.encode(input)).toString();

  static String buildToken(String ts,
          {String secret = JmConstants.tokenSecret,}) =>
      md5Hex(ts + secret);

  /// 32 个 ASCII hex 字符 -> AES-256 key（16/24/32 字节都是合法 key，这里必须用满 32）。
  static Uint8List keyBytes(String ts,
      {String secret = JmConstants.dataSecret,}) {
    final hex = md5Hex(ts + secret);
    return Uint8List.fromList(ascii.encode(hex));
  }

  /// Base64(MIME 容错) -> AES-256-ECB/PKCS7 -> UTF-8
  static String decryptPayload(
    String encoded,
    String ts, {
    String secret = JmConstants.dataSecret,
  }) {
    final bytes = _decodeBase64Lenient(encoded);
    final plain = aesEcbDecrypt(keyBytes(ts, secret: secret), bytes);
    return utf8.decode(plain);
  }

  /// 仅供测试 / fixture 生成使用。
  static String encryptPayload(
    String plainText,
    String ts, {
    String secret = JmConstants.dataSecret,
  }) {
    final encrypted =
        aesEcbEncrypt(keyBytes(ts, secret: secret), utf8.encode(plainText));
    return base64.encode(encrypted);
  }

  static Uint8List _decodeBase64Lenient(String encoded) {
    var clean = encoded.replaceAll(RegExp(r'\s'), '');
    while (clean.length % 4 != 0) {
      clean += '=';
    }
    return base64.decode(clean);
  }

  static Uint8List aesEcbDecrypt(Uint8List key, Uint8List cipherText) {
    if (cipherText.isEmpty || cipherText.length % 16 != 0) {
      throw const FormatException('AES 密文长度不是 16 的整数倍');
    }
    final engine = AESEngine()..init(false, KeyParameter(key));
    final out = Uint8List(cipherText.length);
    final block = Uint8List(16);
    for (var offset = 0; offset < cipherText.length; offset += 16) {
      block.setRange(0, 16, cipherText, offset);
      engine.processBlock(block, 0, out, offset);
    }
    return Uint8List.fromList(_stripPkcs7(out));
  }

  static Uint8List aesEcbEncrypt(Uint8List key, List<int> plainText) {
    final padded = _applyPkcs7(plainText);
    final engine = AESEngine()..init(true, KeyParameter(key));
    final out = Uint8List(padded.length);
    final block = Uint8List(16);
    for (var offset = 0; offset < padded.length; offset += 16) {
      block.setRange(0, 16, padded, offset);
      engine.processBlock(block, 0, out, offset);
    }
    return out;
  }

  static List<int> _applyPkcs7(List<int> input) {
    final pad = 16 - (input.length % 16);
    final result = List<int>.from(input);
    for (var i = 0; i < pad; i++) {
      result.add(pad);
    }
    return result;
  }

  static List<int> _stripPkcs7(Uint8List input) {
    if (input.isEmpty) return const <int>[];
    final pad = input.last;
    if (pad == 0 || pad > 16 || pad > input.length) {
      throw const FormatException('AES 填充非法');
    }
    for (var i = input.length - pad; i < input.length; i++) {
      if (input[i] != pad) throw const FormatException('AES 填充非法');
    }
    return input.sublist(0, input.length - pad);
  }
}
