import 'dart:typed_data';

import '../../core/image/image_processor.dart';
import '../../core/network/api_exception.dart';
import '../../core/utils/logger.dart';
import '../local/progress_store.dart';
import '../models/jm_album_detail.dart';
import '../models/jm_chapter.dart';
import '../sources/jm_api_client.dart';

/// 专辑详情 + 章节 + 阅读器图片（含切片还原）。
class AlbumRepository {
  AlbumRepository({required JmApi api, required ProgressStore progress})
      : _api = api,
        _progress = progress;

  final JmApi _api;
  final ProgressStore _progress;

  final Map<String, int> _scrambleCache = <String, int>{};

  Future<JmAlbumDetail> album(String albumId) => _api.getAlbum(albumId);

  Future<JmChapter> chapter(JmChapterRef reference) => _api.getChapter(reference);

  /// 同一 album 内 photoId == chapterId，scramble 阈值只需取一次。
  Future<int> scrambleId(String photoId) async {
    final cached = _scrambleCache[photoId];
    if (cached != null) return cached;
    final value = await _api.getScrambleId(photoId);
    _scrambleCache[photoId] = value;
    return value;
  }

  /// 下载并还原单页 -> PNG 字节；失败返回 null（阅读器就地重试）。
  Future<Uint8List?> loadPage({
    required String photoId,
    required String filename,
    int? scrambleIdOverride,
  }) async {
    try {
      final raw = await _api.downloadImage(photoId, filename);
      final scramble = scrambleIdOverride ?? await scrambleId(photoId);
      final png = await ImageProcessor.restore(
        RestoreRequest(
          raw: raw,
          scrambleId: scramble,
          photoId: int.tryParse(photoId) ?? 0,
          filename: filename,
        ),
      );
      if (png == null) {
        Log.w('页面 $photoId/$filename 还原失败');
      }
      return png;
    } on JmContentException {
      rethrow;
    } catch (error) {
      Log.w('页面 $photoId/$filename 加载失败：$error');
      return null;
    }
  }

  ReaderProgress? readProgress(String albumId, String chapterId) =>
      _progress.read(albumId, chapterId);

  Future<void> saveProgress(String albumId, String chapterId, int page, int total) {
    return _progress.write(
      albumId,
      chapterId,
      ReaderProgress(
        page: page,
        total: total,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }
}
