import 'dart:io';

import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/constants/jm_constants.dart';
import '../../../core/utils/file_names.dart';
import '../../../core/utils/logger.dart';

/// 导出结果：公共 Documents（MediaStore）或 app 外部目录降级。
class PdfExportResult {
  const PdfExportResult({
    required this.name,
    this.uri,
    this.path,
    this.isPublic = false,
  });

  final String name;

  /// `content://...`（MediaStore）或 `file://...`。
  final String? uri;

  /// 绝对路径（降级时才有）。
  final String? path;

  /// true 表示已写入公共 `Documents/JMComics/`。
  final bool isPublic;

  /// 供打开/分享使用的定位串。
  String? get locator => uri ?? path;
}

/// PDF 落盘契约（对齐 `JmScript/export/DocumentsPdfStore.kt` 的语义）。
abstract class PdfSink {
  /// 写入并返回最终名字（同名自动 `(2)`）。
  Future<PdfExportResult> write(String requestedName, Uint8List bytes);

  /// 打开导出的 PDF。
  Future<bool> open(PdfExportResult result);

  /// 我的页「默认下载目录」展示文案。
  Future<String> describeLocation();
}

/// 原生 MediaStore 通道（android/app 里的 MainActivity 注册 `jm_comic/pdf_store`）。
class MediaStorePdfSink implements PdfSink {
  MediaStorePdfSink({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(_channelName);

  static const String _channelName = 'jm_comic/pdf_store';

  final MethodChannel _channel;

  @override
  Future<PdfExportResult> write(String requestedName, Uint8List bytes) async {
    final response = await _channel.invokeMapMethod<String, dynamic>(
      'savePdf',
      <String, dynamic>{'name': requestedName, 'bytes': bytes},
    );
    if (response == null) {
      throw const FileSystemException('MediaStore 写入失败：通道无响应');
    }
    final name = (response['name'] as String?) ?? requestedName;
    final uri = response['uri'] as String?;
    final path = response['path'] as String?;
    return PdfExportResult(name: name, uri: uri, path: path, isPublic: true);
  }

  @override
  Future<bool> open(PdfExportResult result) async {
    final locator = result.locator;
    if (locator == null || locator.isEmpty) return false;
    try {
      final opened = await _channel.invokeMethod<bool>('openPdf', <String, dynamic>{
        'uri': locator,
      });
      return opened ?? false;
    } catch (error) {
      Log.w('打开 PDF 失败：$error');
      return false;
    }
  }

  @override
  Future<String> describeLocation() async {
    try {
      final label = await _channel.invokeMethod<String>('documentsDir');
      return label ?? JmConstants.exportRelativePath;
    } catch (_) {
      return JmConstants.exportRelativePath;
    }
  }
}

/// 降级实现：写 app 外部目录 `JMComics/`（不需要任何存储权限）。
class FileSystemPdfSink implements PdfSink {
  FileSystemPdfSink({Directory? root}) : _root = root;

  Directory? _root;

  Future<Directory> _ensureRoot() async {
    final cached = _root;
    if (cached != null && cached.existsSync()) return cached;
    final base = await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}${Platform.pathSeparator}${JmConstants.exportDirName}');
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    _root = dir;
    return dir;
  }

  @override
  Future<PdfExportResult> write(String requestedName, Uint8List bytes) async {
    final dir = await _ensureRoot();
    final existing = dir
        .listSync()
        .whereType<File>()
        .map((file) => file.uri.pathSegments.last)
        .toList(growable: false);
    final name = nextAvailablePdfName(requestedName, existing);
    final file = File('${dir.path}${Platform.pathSeparator}$name');
    await file.writeAsBytes(bytes, flush: true);
    return PdfExportResult(
      name: name,
      path: file.path,
      uri: file.uri.toString(),
    );
  }

  @override
  Future<bool> open(PdfExportResult result) async {
    final path = result.path;
    if (path == null) return false;
    final response = await OpenFilex.open(path);
    return response.type == ResultType.done;
  }

  @override
  Future<String> describeLocation() async {
    final dir = await _ensureRoot();
    return dir.path;
  }
}

/// 首选 MediaStore，插件/原生通道不可用时降级到 app 目录（PLAN §11）。
class FallbackPdfSink implements PdfSink {
  FallbackPdfSink({PdfSink? primary, PdfSink? fallback})
      : _primary = primary ?? MediaStorePdfSink(),
        _fallback = fallback ?? FileSystemPdfSink();

  final PdfSink _primary;
  final PdfSink _fallback;

  @override
  Future<PdfExportResult> write(String requestedName, Uint8List bytes) async {
    try {
      return await _primary.write(requestedName, bytes);
    } catch (error) {
      Log.w('MediaStore 写入失败，本次降级到应用目录（保留 primary 供下次重试）：$error');
      return _fallback.write(requestedName, bytes);
    }
  }

  @override
  Future<bool> open(PdfExportResult result) async {
    if (result.uri != null && result.uri!.startsWith('content://')) {
      final opened = await MediaStorePdfSink().open(result);
      if (opened) return true;
    }
    return _fallback.open(result);
  }

  @override
  Future<String> describeLocation() async {
    try {
      return await _primary.describeLocation();
    } catch (_) {
      return _fallback.describeLocation();
    }
  }
}

/// 内存实现（单测 / 预览用）。
class MemoryPdfSink implements PdfSink {
  final Map<String, Uint8List> files = <String, Uint8List>{};
  int openCount = 0;

  @override
  Future<PdfExportResult> write(String requestedName, Uint8List bytes) async {
    final name = nextAvailablePdfName(requestedName, files.keys);
    files[name] = bytes;
    return PdfExportResult(
      name: name,
      path: '/memory/$name',
      uri: 'file:///memory/$name',
    );
  }

  @override
  Future<bool> open(PdfExportResult result) async {
    openCount++;
    return true;
  }

  @override
  Future<String> describeLocation() async => '/memory';
}
