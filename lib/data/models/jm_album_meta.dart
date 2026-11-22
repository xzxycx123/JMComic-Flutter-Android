/// `/album` 的轻量元数据：卡片批量补数用（点赞数 + 作品标签）。
///
/// 列表接口（`/promote`、`/latest`、`/categories/filter`、`/search`）既不带
/// `likes` 也不带 `tags`，卡片上的「喜歡」数和左上角标签都靠这一次 `/album` 补。
class JmAlbumMeta {
  const JmAlbumMeta({
    this.likes = 0,
    this.tags = const <String>[],
  });

  /// 「喜歡」数（缺失/负数按 0）。
  final int likes;

  /// 作品标签（`泳裝 / 百合 / 扶他 …`），不含分类名。
  final List<String> tags;

  static const JmAlbumMeta empty = JmAlbumMeta();
}
