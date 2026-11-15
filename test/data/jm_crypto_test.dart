import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jm_comic/data/sources/jm_crypto.dart';

/// 2026-11-15 实网复核：JM 的 AES 是 **AES-256-ECB**，key = `ASCII(md5hex(ts + secret))` 32 个字节。
///
/// 下面两条密文由 .NET 侧独立实现生成（同 key 派生规则），用来锁死「不能截断成 16 字节」这件事：
/// 截断成 AES-128 时 PKCS7 去填充会直接抛错，表现就是「HTTP 200 但所有线路都解密失败」。
const String _vector1Ts = '1700566805';
const String _vector1Plain =
    '{"jm3_version":"2.1.13","img_host":"cdn-msp.jmdanjonproxy.vip"}';
const String _vector1Cipher =
    '93N8CDjQgBCHBfqIhTgwn1rIlOzd7fG+LO7ActJs9z88yUm1bz3S9niJrCq7AZbeoBHABHLUKhAt0YRPLYRzFQ==';

const String _vector2Plain =
    '{"Setting":["www.cdnutc.cc"],"Server":["www.cdnutc.cc"],"jm3_Server":[["www.cdnutc.cc","線路2"]]}';
const String _vector2Cipher =
    'X+bnzYIcwF6C7Rd3T7njPEvScsq31SpyA8ytIx7fWFhESrgeYQqsngATU8M0oljdoMNXyb63cqLg2gY+Lkefr2K2tqttrGo5FOLPNZ+tf9EhkqLNQBg8q6Tx5wbCPr+QmNGDvSXAwp6T0MeV1YopFg==';

void main() {
  group('token', () {
    test('与参考实现一致（PLAN §10.1）', () {
      expect(JmCrypto.buildToken('1700566805'),
          'cce2cb071cd0cf371a2e34fd5ad66fd6',);
    });
  });

  group('AES-256-ECB/PKCS7', () {
    test('key 用满 md5hex 的 32 个 ASCII 字节', () {
      final key = JmCrypto.keyBytes('1700566805');
      expect(key.length, 32);
      expect(String.fromCharCodes(key),
          JmCrypto.md5Hex('1700566805185Hcomic3PAPP7R'),);
    });

    test('解密 .NET 侧生成的密文（接口 data）', () {
      expect(
          JmCrypto.decryptPayload(_vector1Cipher, _vector1Ts), _vector1Plain,);
    });

    test('解密 .NET 侧生成的密文（域名服务，ts 为空）', () {
      expect(
        JmCrypto.decryptPayload(
          _vector2Cipher,
          '',
          secret: 'diosfjckwpqpdfjkvnqQjsik',
        ),
        _vector2Plain,
      );
    });

    test('加密后能解回原文', () {
      const ts = '1700566805';
      const plain = '{"name":"Test Comic","id":123}';
      final encoded = JmCrypto.encryptPayload(plain, ts);
      expect(JmCrypto.decryptPayload(encoded, ts), plain);
    });

    test('MIME 容错：带空白与缺 pad 的 Base64 也能解', () {
      const ts = '1700566805';
      const plain = '{"ok":true}';
      final encoded = JmCrypto.encryptPayload(plain, ts);

      final withWhitespace =
          '${encoded.substring(0, 4)} \n ${encoded.substring(4)}';
      expect(JmCrypto.decryptPayload(withWhitespace, ts), plain);

      final withoutPadding = encoded.replaceAll('=', '');
      expect(JmCrypto.decryptPayload(withoutPadding, ts), plain);
    });

    test('真实 /setting 响应能解出 jm3_version 与 img_host', () {
      final file = File('test/fixtures/setting_envelope_live.json');
      expect(file.existsSync(), isTrue, reason: '缺少实网采样 fixture');
      final fixture =
          jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      final envelope = fixture['envelope'] as Map<String, dynamic>;
      final ts = fixture['ts'] as String;
      expect(envelope['code'], 200);

      final plain = JmCrypto.decryptPayload(envelope['data'] as String, ts);
      final setting = jsonDecode(plain) as Map<String, dynamic>;
      expect(setting['jm3_version'], isNotEmpty);
      expect((setting['img_host'] as String).contains('.'), isTrue);
    });
  });
}
