import '../../core/icons/app_icons.dart';

/// 阅读器两种模式（PLAN §7.6）。
enum ReaderMode {
  paged('paged', '左右翻页', AppIcons.pageMode),
  vertical('vertical', '上下滚动', AppIcons.scrollMode);

  const ReaderMode(this.code, this.label, this.icon);

  final String code;
  final String label;
  final String icon;

  static ReaderMode fromCode(String? code) {
    for (final mode in ReaderMode.values) {
      if (mode.code == code) return mode;
    }
    return ReaderMode.paged;
  }

  ReaderMode get toggled => this == ReaderMode.paged ? ReaderMode.vertical : ReaderMode.paged;
}

/// 阅读器入参（路由 query 与 provider family 共用）。
class ReaderArgs {
  const ReaderArgs({
    required this.albumId,
    required this.chapterId,
    this.title = '',
    this.albumTitle = '',
    this.page = 1,
  });

  final String albumId;
  final String chapterId;
  final String title;
  final String albumTitle;
  final int page;

  factory ReaderArgs.fromQuery(Map<String, String> query) => ReaderArgs(
        albumId: query['album'] ?? '',
        chapterId: query['chapter'] ?? '',
        title: query['title'] ?? '',
        albumTitle: query['albumTitle'] ?? '',
        page: int.tryParse(query['page'] ?? '') ?? 1,
      );

  Map<String, String> toQuery() => <String, String>{
        'album': albumId,
        'chapter': chapterId,
        if (title.isNotEmpty) 'title': title,
        if (albumTitle.isNotEmpty) 'albumTitle': albumTitle,
        'page': '$page',
      };

  String get route => '/reader?${Uri(queryParameters: toQuery()).query}';

  @override
  bool operator ==(Object other) =>
      other is ReaderArgs &&
      other.albumId == albumId &&
      other.chapterId == chapterId &&
      other.page == page;

  @override
  int get hashCode => Object.hash(albumId, chapterId, page);
}
