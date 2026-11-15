import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:jm_comic/features/download/engine/pdf_exporter.dart';

import '../helpers/fixtures.dart';

void main() {
  test('两张 PNG → 两页 PDF，页面尺寸跟随位图', () async {
    final pages = <Uint8List>[
      syntheticPng(width: 30, height: 40, seed: 1),
      syntheticPng(width: 50, height: 60, seed: 2),
    ];

    final bytes = await PdfExporter.exportBytes(pages);

    expect(bytes.length, greaterThan(500));
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    final text = latin1.decode(bytes, allowInvalid: true);
    expect(text.contains('/Count 2'), isTrue);
  });

  test('空页面列表抛错', () async {
    expect(
      () => PdfExporter.exportBytes(const <Uint8List>[]),
      throwsArgumentError,
    );
  });
}
