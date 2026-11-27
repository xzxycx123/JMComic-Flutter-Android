import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import '../../core/utils/file_names.dart';
import '../../data/sources/reader_image_store_channel.dart';

/// 一张已经落盘的当页图片。
class SavedReaderImage {
  const SavedReaderImage({required this.name, required this.path});

  final String name;

  /// Android 公共存储的相对路径，或其他平台的绝对路径。
  final String path;

  String get displayPath => path;
}

/// 阅读器「下载当页图片」的落盘器。
///
/// 目录来自设置（默认 `Pictures/JMComicDownloader/`）：
/// - Android：通过 MediaStore 保存到公共存储。
/// - 其他平台：保存到应用文档目录。
class ReaderImageSaver {
  ReaderImageSaver({required this.directory, Directory? root}) : _root = root;

  /// 当前设置的目录（运行时可被设置页改掉）。
  final String Function() directory;

  /// 测试注入：所有文件落到这个根目录下。
  final Directory? _root;

  Future<SavedReaderImage> save(String fileName, Uint8List bytes) async {
    final relative = normalizeSaveDir(directory());
    if (_root == null && Platform.isAndroid) {
      final saved = await const ReaderImageStoreChannel().savePng(
        name: fileName,
        directory: relative,
        bytes: bytes,
      );
      return SavedReaderImage(name: saved.name, path: saved.path);
    }

    final root = _root ?? await getApplicationDocumentsDirectory();
    final dir = await Directory(
      '${root.path}${Platform.pathSeparator}$relative',
    ).create(recursive: true);
    final file = File('${dir.path}${Platform.pathSeparator}$fileName');
    await file.writeAsBytes(bytes, flush: true);
    return SavedReaderImage(name: fileName, path: file.path);
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
