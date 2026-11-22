import 'dart:typed_data';

import '../../core/image/image_processor.dart';
import '../../core/network/api_exception.dart';
import '../../core/utils/logger.dart';
import '../local/progress_store.dart';
import '../models/jm_album_detail.dart';
import '../models/jm_album_meta.dart';
import '../models/jm_chapter.dart';
import '../models/jm_comment.dart';
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

  /// 卡片「喜歡」数的精确值（JmAPI `/album.likes`）：列表接口不带计数。
  Future<int> likes(String albumId) => _api.fetchAlbumLikes(albumId);

  /// 卡片批量补数：点赞数 + 作品标签（同一次 `/album` 请求）。
  Future<JmAlbumMeta> meta(String albumId) => _api.fetchAlbumMeta(albumId);

  Future<JmChapter> chapter(JmChapterRef reference) => _api.getChapter(reference);

  // ---------------------------------------------------------------- 互动
  /// 点赞（`POST /like`，需要登录；服务端不返回计数，UI 侧乐观 +1）。
  Future<void> like(String albumId) => _api.likeAlbum(albumId);

  Future<JmCommentPage> comments(String albumId, {int page = 1}) =>
      _api.fetchComments(albumId: albumId, page: page);

  Future<String> postComment({
    required String albumId,
    required String content,
    bool spoiler = false,
    String? parentId,
  }) =>
      _api.postComment(
        albumId: albumId,
        content: content,
        spoiler: spoiler,
        parentId: parentId,
      );

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

  Future<void> saveProgress(
    String albumId,
    String chapterId,
    int page,
    int total, {
    String albumTitle = '',
    String chapterTitle = '',
  }) {
    return _progress.write(
      albumId,
      chapterId,
      ReaderProgress(
        page: page,
        total: total,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
        albumTitle: albumTitle,
        chapterTitle: chapterTitle,
      ),
    );
  }

  /// 阅读历史（按最近阅读倒序）。
  List<ReadingHistoryEntry> readingHistory() => _progress.entries();

  Future<void> removeHistory(String albumId, String chapterId) =>
      _progress.remove(albumId, chapterId);

  Future<void> clearHistory() => _progress.clear();
}
