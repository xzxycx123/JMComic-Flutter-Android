import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import '../../core/utils/file_names.dart';

/// 一张已经落盘的当页图片。
class SavedReaderImage {
  const SavedReaderImage({required this.name, required this.path});

  final String name;

  /// 绝对路径（展示 / 调试用）。
  final String path;

  /// 相对存储根的展示路径（`Pictures/JMComicDownloader/xxx.png`）。
  String get displayPath {
    final marker = normalizeSaveDir('');
    final index = path.lastIndexOf(marker);
    return index >= 0 ? path.substring(index) : path;
  }
}

/// 阅读器「下载当页图片」的落盘器。
///
/// 目录来自设置（默认 `Pictures/JMComicDownloader/`）：
/// - Android：先试公共 `/storage/emulated/0/<dir>`，权限不足自动降级到 App 外部目录；
/// - 其它平台：App 文档目录。
class ReaderImageSaver {
  ReaderImageSaver({required this.directory, Directory? root}) : _root = root;

  /// 当前设置的目录（运行时可被设置页改掉）。
  final String Function() directory;

  /// 测试注入：所有文件落到这个根目录下。
  final Directory? _root;

  Future<SavedReaderImage> save(String fileName, Uint8List bytes) async {
    final dir = await targetDirectory();
    final file = File('${dir.path}${Platform.pathSeparator}$fileName');
    await file.writeAsBytes(bytes, flush: true);
    return SavedReaderImage(name: fileName, path: file.path);
  }

  /// 解析并创建目标目录。
  Future<Directory> targetDirectory() async {
    final relative = normalizeSaveDir(directory());
    final root = _root;
    if (root != null) {
      return _ensure(
        Directory('${root.path}${Platform.pathSeparator}$relative'),
      );
    }
    if (Platform.isAndroid) {
      final public = Directory('/storage/emulated/0');
      if (public.existsSync()) {
        try {
          return await _ensure(
            Directory('${public.path}${Platform.pathSeparator}$relative'),
          );
        } catch (_) {
          // 没有存储权限：降级到 App 外部目录，不让保存直接失败。
        }
      }
    }
    final base = await getExternalStorageDirectory() ??
        await getApplicationDocumentsDirectory();
    return _ensure(Directory('${base.path}${Platform.pathSeparator}$relative'));
  }

  static Future<Directory> _ensure(Directory dir) async {
    if (!dir.existsSync()) await dir.create(recursive: true);
    return dir;
  }
}

/// 内存实现（单测 / 预览用）。
class MemoryReaderImageSaver extends ReaderImageSaver {
  MemoryReaderImageSaver()
      : super(
          directory: () => defaultSaveImageDir,
        );

  final Map<String, Uint8List> files = <String, Uint8List>{};

  @override
  Future<SavedReaderImage> save(String fileName, Uint8List bytes) async {
    files[fileName] = bytes;
    return SavedReaderImage(name: fileName, path: '/memory/$fileName');
  }
}
