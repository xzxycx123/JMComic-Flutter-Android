import 'package:flutter/services.dart';

/// 通过 Android MediaStore 把阅读器图片发布到公共存储。
class ReaderImageStoreChannel {
  const ReaderImageStoreChannel({
    MethodChannel channel = const MethodChannel('jm_comic/reader_image_store'),
  }) : _channel = channel;

  final MethodChannel _channel;

  Future<({String name, String path})> savePng({
    required String name,
    required String directory,
    required Uint8List bytes,
  }) async {
    final saved = await _channel.invokeMapMethod<String, String>(
      'savePng',
      <String, Object>{'name': name, 'directory': directory, 'bytes': bytes},
    );
    final savedName = saved?['name'];
    final savedPath = saved?['path'];
    if (savedName == null ||
        savedName.isEmpty ||
        savedPath == null ||
        savedPath.isEmpty) {
      throw PlatformException(code: 'save_failed', message: '系统未返回图片保存位置');
    }
    return (name: savedName, path: savedPath);
  }
}
