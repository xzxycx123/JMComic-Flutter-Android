import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jm_comic/data/sources/reader_image_store_channel.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('jm_comic/reader_image_store');
  const store = ReaderImageStoreChannel();
  final bytes = Uint8List.fromList([1, 2, 3]);

  tearDown(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  test('提交图片和自定义目录，返回系统实际保存的位置', () async {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (call) async {
        expect(call.method, 'savePng');
        expect(call.arguments, {
          'name': 'page.png',
          'directory': 'Download/JMComic',
          'bytes': bytes,
        });
        return {
          'name': 'page (1).png',
          'path': 'Download/JMComic/page (1).png',
        };
      },
    );

    final saved = await store.savePng(
      name: 'page.png',
      directory: 'Download/JMComic',
      bytes: bytes,
    );
    expect(
      saved,
      (name: 'page (1).png', path: 'Download/JMComic/page (1).png'),
    );
  });

  test('原生通道未确认文件位置时保存失败', () async {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (_) async => null,
    );

    await expectLater(
      store.savePng(
        name: 'page.png',
        directory: 'Pictures/JMComicDownloader',
        bytes: bytes,
      ),
      throwsA(isA<PlatformException>()),
    );
  });
}
