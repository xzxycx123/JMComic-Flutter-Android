import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:jm_comic/core/constants/jm_constants.dart';
import 'package:jm_comic/core/network/api_exception.dart';
import 'package:jm_comic/data/models/jm_album_detail.dart';
import 'package:jm_comic/data/models/jm_album_summary.dart';
import 'package:jm_comic/data/models/jm_category.dart';
import 'package:jm_comic/data/models/jm_chapter.dart';
import 'package:jm_comic/data/models/jm_favorite_list.dart';
import 'package:jm_comic/data/models/jm_promote_module.dart';
import 'package:jm_comic/data/models/jm_search_page.dart';
import 'package:jm_comic/data/models/user_session.dart';
import 'package:jm_comic/data/sources/jm_api_client.dart';
import 'package:jm_comic/data/sources/jm_response_parser.dart';

/// 测试 fixture 读取器（fixtures 目录与 lib 同级，用相对文件系统路径读）。
abstract final class Fixtures {
  static Directory get _dir => Directory('test/fixtures');

  static String text(String name) =>
      File('${_dir.path}/$name').readAsStringSync();

  static dynamic json(String name) => jsonDecode(text(name));

  static Map<String, dynamic> map(String name) =>
      json(name) as Map<String, dynamic>;

  static List<dynamic> list(String name) => json(name) as List<dynamic>;

  static List<dynamic> promote() => list('promote.json');

  static List<dynamic> latest() => list('latest_p1.json');

  static Map<String, dynamic> categories() => map('categories.json');

  static Map<String, dynamic> filter() => map('filter_p1.json');

  static Map<String, dynamic> album() => map('album.json');

  static Map<String, dynamic> chapter() => map('chapter.json');
}

/// 用 `image` 包合成一张小 PNG（下载流水线测试用）。
Uint8List syntheticPng({
  int width = 24,
  int height = 36,
  int seed = 7,
}) {
  final image = img.Image(width: width, height: height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      image.setPixelRgb(x, y, (x * 7 + seed) % 256, (y * 5 + seed) % 256,
          (x + y + seed) % 256,);
    }
  }
  return Uint8List.fromList(img.encodePng(image));
}

/// 按 PLAN §5.7 的还原算法把原图「切」回去（用于 image_processor 往返断言）。
Uint8List scramblePng(Uint8List original, {required int segments}) {
  final source = img.decodePng(original)!;
  final output = img.Image(width: source.width, height: source.height);
  final layout = List.generate(segments, (index) {
    final base = source.height ~/ segments;
    final remainder = source.height % segments;
    var sliceHeight = base;
    var dstTop = base * index;
    final srcTop = source.height - (base * (index + 1)) - remainder;
    if (index == 0) {
      sliceHeight += remainder;
    } else {
      dstTop += remainder;
    }
    return (srcTop: srcTop, dstTop: dstTop, height: sliceHeight);
  });
  for (final slice in layout) {
    final piece = img.copyCrop(
      source,
      x: 0,
      y: slice.dstTop,
      width: source.width,
      height: slice.height,
    );
    img.compositeImage(output, piece, dstY: slice.srcTop);
  }
  return Uint8List.fromList(img.encodePng(output));
}

/// 可直接驱动下载引擎的 fake API（2 章 × 3 页，PNG 直通不切片）。
class FakeJmApi implements JmApi {
  FakeJmApi({
    this.chapterCount = 2,
    this.pagesPerChapter = 3,
    this.failPages = 0,
    this.emptyCategories = false,
    this.failAll = false,
    this.failEveryPage = false,
    this.emptyAfterFirstPage = false,
    this.gate,
    this.loggedIn = false,
    this.forcedToggleType,
    Set<String>? serverFavorites,
  }) : serverFavorites = serverFavorites ?? <String>{};

  final int chapterCount;
  final int pagesPerChapter;
  final int failPages;

  /// /categories 返回空（验证固定分类兜底）。
  final bool emptyCategories;

  /// 所有端点抛网络异常（验证整页错误态）。
  final bool failAll;

  /// 每一页都解码/下载失败（验证 PLAN §11 的 ≥3 页失败即任务失败）。
  final bool failEveryPage;

  /// 第 2 页起返回空 content（验证服务端到底标记）。
  final bool emptyAfterFirstPage;

  /// 页面下载闸门：不 complete 就一直挂起，用于验证取消。
  final Completer<void>? gate;

  /// 是否已登录（收藏接口依赖）。
  bool loggedIn;

  /// 强制返回与操作相反的 toggle 结果（用于验证反向自愈）。
  String? forcedToggleType;

  /// 服务端收藏集合（toggle 会真实增删）。
  final Set<String> serverFavorites;

  final Map<String, String> _cookies = <String, String>{};

  int downloadCalls = 0;
  int scrambleCalls = 0;
  int filterCalls = 0;

  void _throwIfFailing() {
    if (failAll) {
      throw const JmApiException('所有 API 线路均连接失败', network: true);
    }
  }

  @override
  String get apiHost => 'www.cdnbtd.cc';

  @override
  List<String> get availableHosts => const <String>[
        'www.cdnbtd.cc',
        'www.cdnutc.cc',
        'www.cdngwc.net',
        'www.cdngwc.club',
      ];

  @override
  Future<bool> switchApiHost(String host) async => true;

  @override
  String get imageHost => 'cdn-msp.jmdanjonproxy.xyz';

  @override
  Map<String, String> get imageHeaders =>
      <String, String>{'User-Agent': 'fake'};

  @override
  UserSession get session => UserSession(
        apiHost: apiHost,
        imageHost: imageHost,
        appVersion: '2.1.13',
        ready: true,
      );

  @override
  Future<Map<String, dynamic>> login({
    required String username,
    required String password,
  }) async {
    if (username.isEmpty || password.isEmpty) {
      throw const JmContentException('用户名和密码不能为空');
    }
    loggedIn = true;
    _cookies['AVS'] = 'fake-avs';
    return <String, dynamic>{
      'uid': 42,
      'username': username,
      'album_favorites': serverFavorites.length,
      'album_favorites_max': 500,
      'level': 3,
      'level_name': 'LV3',
      's': 'fake-avs',
    };
  }

  @override
  Future<JmFavoriteList> fetchFavorites({
    int page = 1,
    String order = 'mr',
    int folderId = 0,
  }) async {
    if (!loggedIn) {
      throw const JmContentException('JM 接口错误：请先登录');
    }
    final items = serverFavorites
        .map((id) => JmAlbumSummary(id: id, title: 'JM$id'))
        .toList(growable: false);
    return JmFavoriteList(
      count: items.length,
      total: items.length,
      items: page == 1 ? items : const <JmAlbumSummary>[],
      page: page,
    );
  }

  @override
  Future<String> toggleFavorite(String albumId) async {
    if (!loggedIn) {
      throw const JmContentException('JM 接口错误：请先登录');
    }
    final forced = forcedToggleType;
    if (forced != null) {
      forcedToggleType = null;
      return forced;
    }
    if (serverFavorites.remove(albumId)) return 'remove';
    serverFavorites.add(albumId);
    return 'add';
  }

  @override
  Future<bool> pingFavorite() async => loggedIn;

  @override
  Future<void> setCookie(String name, String value) async {
    _cookies[name] = value;
  }

  @override
  Map<String, String> get cookieSnapshot => Map<String, String>.unmodifiable(_cookies);

  @override
  void restoreCookies(Map<String, String> cookies) {
    _cookies
      ..clear()
      ..addAll(cookies);
  }
  @override
  Future<void> prepare() async {}

  @override
  Future<JmAlbumDetail> getAlbum(String albumId) async {
    final chapters = List<JmChapterRef>.generate(
      chapterCount,
      (index) => JmChapterRef(
          id: '${albumId}0$index', sort: index + 1, title: '第 ${index + 1} 话',),
    );
    return JmAlbumDetail(
      id: albumId,
      title: '测试用单本漫画',
      totalPages: chapterCount * pagesPerChapter,
      chapters: chapterCount == 1
          ? <JmChapterRef>[JmChapterRef(id: albumId, sort: 1, title: '全一话')]
          : chapters,
    );
  }

  @override
  Future<JmChapter> getChapter(JmChapterRef reference) async {
    return JmChapter(
      id: reference.id,
      title: reference.title,
      images: List<String>.generate(
        pagesPerChapter,
        (index) => '0000${index + 1}.webp',
      ),
    );
  }

  @override
  Future<int> getScrambleId(String photoId) async {
    scrambleCalls++;
    return 220980;
  }

  @override
  Future<Uint8List> downloadImage(String photoId, String filename) async {
    downloadCalls++;
    final gate = this.gate;
    if (gate != null) await gate.future;
    if (failEveryPage || downloadCalls <= failPages) {
      throw StateError('模拟下载失败');
    }
    return syntheticPng(seed: downloadCalls);
  }

  @override
  String coverUrl(String albumId) => 'https://cdn.example/$albumId.jpg';

  @override
  String photoUrl(String photoId, String filename) =>
      'https://cdn.example/$photoId/$filename';

  @override
  Future<List<JmPromoteModule>> fetchPromote() async {
    _throwIfFailing();
    return JmResponseParser.promote(Fixtures.promote());
  }

  @override
  Future<List<JmAlbumSummary>> fetchLatest({int page = 1}) async {
    _throwIfFailing();
    return JmResponseParser.albumList(Fixtures.latest());
  }

  @override
  Future<List<JmCategory>> fetchCategories() async {
    _throwIfFailing();
    if (emptyCategories) return <JmCategory>[];
    return JmResponseParser.categories(Fixtures.categories());
  }

  @override
  Future<JmSearchPage> fetchFilter({
    int page = 1,
    String category = '0',
    AlbumOrder order = AlbumOrder.latestUpdate,
  }) async {
    _throwIfFailing();
    filterCalls++;
    if (emptyAfterFirstPage && page > 1) {
      return JmSearchPage(
        query: '',
        total: 0,
        content: const <JmAlbumSummary>[],
        page: page,
      );
    }
    return JmResponseParser.searchPage(Fixtures.filter(), page: page);
  }

  @override
  Future<JmSearchPage> search({
    required String query,
    int page = 1,
    AlbumOrder order = AlbumOrder.latestUpdate,
  }) async {
    _throwIfFailing();
    return JmResponseParser.searchPage(Fixtures.filter(),
        page: page, query: query,);
  }
}

/// 解析后的首页数据（repository 测试用）。
List<dynamic> parsePromoteFixture() =>
    JmResponseParser.promote(Fixtures.promote());
