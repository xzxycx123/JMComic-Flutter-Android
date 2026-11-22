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
import 'package:jm_comic/data/models/jm_comment.dart';
import 'package:jm_comic/data/models/jm_daily.dart';
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

/// 造一份 `/daily` 风格的当月记录：1..[daysInMonth] 按 7 天切块。
JmDailyState buildFakeDaily({
  Set<int> signed = const <int>{},
  Set<int> bonus = const <int>{},
  int dailyId = 74,
  int daysInMonth = 30,
  int? coin,
  String eventName = '11月-签到礼',
}) {
  final rows = <List<JmDailyDay>>[];
  var row = <JmDailyDay>[];
  for (var day = 1; day <= daysInMonth; day++) {
    row.add(
      JmDailyDay(
        day: day,
        signed: signed.contains(day),
        bonus: bonus.contains(day),
      ),
    );
    if (row.length == 7) {
      rows.add(row);
      row = <JmDailyDay>[];
    }
  }
  if (row.isNotEmpty) rows.add(row);
  return JmDailyState(
    dailyId: dailyId,
    rows: rows,
    eventName: eventName,
    makeupLimit: 5,
    makeupAvailable: true,
    coin: coin,
  );
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
      image.setPixelRgb(
        x,
        y,
        (x * 7 + seed) % 256,
        (y * 5 + seed) % 256,
        (x + y + seed) % 256,
      );
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

  /// 收藏列表返回业务错误（用于验证「非鉴权错误不踢下线」）。
  String? favoritesError;

  /// 服务端收藏集合（toggle 会真实增删）。
  final Set<String> serverFavorites;

  /// `/daily` 返回的当月记录；为空时按「全部未签」造一份。
  JmDailyState? dailyState;

  /// 「今天」是几号（与测试注入的时钟一致；签到成功后标记这天已签）。
  int? dailyToday;

  /// `/daily_chk` 的服务端文案。
  String dailyCheckInMessage = '簽到成功';

  /// `/daily_chk` 是否真的把今天标记为已签（false = 服务端没生效）。
  bool dailyCheckInApplies = true;

  /// `/daily_chk` 是否抛业务错误（验证错误提示）。
  String? dailyCheckInError;

  /// `/daily` 是否抛业务错误（验证加载失败 / 重试）。
  String? dailyError;

  /// 服务端下发的 JCoin 余额（`/daily` 里可选字段）。
  int? dailyCoin;

  /// 服务端下发的最新 JCoin 余额（`/daily_chk` 响应里可选字段）。
  int? dailyCheckInCoin;

  int dailyCalls = 0;
  int dailyCheckInCalls = 0;

  /// 每次 `/daily_chk` 的 form 快照（`user_id=..&daily_id=..`），供断言参数。
  final List<String> dailyCheckInPayloads = <String>[];

  final Map<String, String> _cookies = <String, String>{};

  int downloadCalls = 0;
  int scrambleCalls = 0;
  int filterCalls = 0;
  int loginCalls = 0;

  /// `/categories/filter` 入参快照：断言「点分类真的带 slug 重查」。
  final List<({String slug, AlbumOrder order, int page})> filterQueries =
      <({String slug, AlbumOrder order, int page})>[];

  /// 最近一次 `/categories/filter` 的分类 slug（空串 = 不过滤）。
  String? get lastCategorySlug =>
      filterQueries.isEmpty ? null : filterQueries.last.slug;

  /// 最近一次 `/categories/filter` 的排序。
  AlbumOrder? get lastFilterOrder =>
      filterQueries.isEmpty ? null : filterQueries.last.order;

  /// 模拟服务端按 slug 过滤：fixture 里只有「同人」「單本」两条分类。
  ///
  /// 二级分类是 `父slug_子slug` 拼接（`doujin_chinese`），服务端按父类降级过滤。
  static const Map<String, String> slugToCategoryId = <String, String>{
    'doujin': '1',
    'single': '2',
    'doujin_chinese': '1',
  };

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
    loginCalls++;
    loggedIn = true;
    _cookies['AVS'] = 'fake-avs';
    return <String, dynamic>{
      'uid': 42,
      'username': username,
      'album_favorites': serverFavorites.length,
      'album_favorites_max': 500,
      'level': 3,
      'level_name': 'LV3',
      'coin': 320,
      's': 'fake-avs',
    };
  }

  @override
  Future<JmFavoriteList> fetchFavorites({
    int page = 1,
    String order = 'mr',
    int folderId = 0,
  }) async {
    final failure = favoritesError;
    if (failure != null) throw JmContentException(failure);
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
  Future<JmDailyState> fetchDaily({required int userId}) async {
    _throwIfFailing();
    if (!loggedIn) {
      throw const JmContentException('JM 接口错误：请先登录');
    }
    dailyCalls++;
    final failure = dailyError;
    if (failure != null) throw JmContentException(failure);
    final state = dailyState ??= buildFakeDaily();
    return dailyCoin == null ? state : state.copyWith(coin: dailyCoin);
  }

  @override
  Future<JmCheckInResult> checkInDaily({
    required int userId,
    required int dailyId,
  }) async {
    _throwIfFailing();
    if (!loggedIn) {
      throw const JmContentException('JM 接口错误：请先登录');
    }
    dailyCheckInCalls++;
    dailyCheckInPayloads.add('user_id=$userId&daily_id=$dailyId');
    final failure = dailyCheckInError;
    if (failure != null) throw JmContentException(failure);
    if (dailyCheckInApplies) {
      final current = dailyState ??= buildFakeDaily();
      dailyState = current.withSignedDay(dailyToday ?? 1);
    }
    return JmCheckInResult(
      message: dailyCheckInMessage,
      alreadySigned: dailyCheckInMessage.contains('已經簽到過了'),
      coin: dailyCheckInCoin,
    );
  }

  // ---------------------------------------------------------------- 互动
  /// 点赞记录（测试断言用）。
  final Set<String> likedAlbums = <String>{};

  /// 发出去的评论（测试断言用）。
  final List<JmComment> postedComments = <JmComment>[];

  @override
  Future<void> likeAlbum(String albumId) async {
    if (!loggedIn) {
      throw const JmContentException('登录状态已失效，请重新登录');
    }
    likedAlbums.add(albumId);
  }

  // ---------------------------------------------------------------- 喜欢数（JmAPI）
  /// `/album.likes` 的逐本返回值；没配置的走 [fallbackLikes]。
  final Map<String, int> likesByAlbum = <String, int>{};

  /// 未显式配置时的点赞数。
  int fallbackLikes = 0;

  /// 这些 id 的取数请求直接抛网络异常（验证重试 / 放弃）。
  final Set<String> likesErrors = <String>{};

  /// 每个 id 只失败前 N 次（验证「失败后下次 build 再试一次」）。
  final Map<String, int> likesTransientFailures = <String, int>{};

  /// 人为延迟（验证并发上限）。
  Duration likesDelay = Duration.zero;

  int likesCalls = 0;
  final List<String> likesRequests = <String>[];

  @override
  Future<int> fetchAlbumLikes(String albumId) async {
    likesCalls++;
    likesRequests.add(albumId);
    if (likesDelay > Duration.zero) {
      await Future<void>.delayed(likesDelay);
    }
    _throwIfFailing();
    final remainingFailures = likesTransientFailures[albumId] ?? 0;
    if (remainingFailures > 0) {
      likesTransientFailures[albumId] = remainingFailures - 1;
      throw const JmApiException('喜欢数取数失败（模拟）', network: true);
    }
    if (likesErrors.contains(albumId)) {
      throw const JmApiException('喜欢数取数失败（模拟）', network: true);
    }
    return likesByAlbum[albumId] ?? fallbackLikes;
  }

  @override
  Future<JmCommentPage> fetchComments({
    required String albumId,
    int page = 1,
    String mode = 'manhua',
  }) async {
    if (page > 1) {
      return const JmCommentPage(items: <JmComment>[], total: 3, page: 2);
    }
    return JmCommentPage(
      total: 3,
      page: 1,
      items: <JmComment>[
        JmComment(
          id: '9001',
          albumId: albumId,
          nickname: '测试用户',
          content: '第一条测试评论',
          likes: 2,
          createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000 - 120,
        ),
        const JmComment(id: '9002', albumId: '1', content: '第二条测试评论'),
        const JmComment(
          id: '9003',
          albumId: '1',
          content: '剧透评论',
          spoiler: true,
        ),
      ],
    );
  }

  @override
  Future<String> postComment({
    required String albumId,
    required String content,
    bool spoiler = false,
    String? parentId,
  }) async {
    if (!loggedIn) {
      throw const JmContentException('登录状态已失效，请重新登录');
    }
    postedComments.add(
      JmComment(
        id: '${postedComments.length + 1}',
        albumId: albumId,
        content: content,
      ),
    );
    return '評論成功!';
  }

  @override
  Future<void> setCookie(String name, String value) async {
    _cookies[name] = value;
  }

  @override
  Map<String, String> get cookieSnapshot =>
      Map<String, String>.unmodifiable(_cookies);

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
        id: '${albumId}0$index',
        sort: index + 1,
        title: '第 ${index + 1} 话',
      ),
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
    String categorySlug = '',
    AlbumOrder order = AlbumOrder.latestUpdate,
  }) async {
    _throwIfFailing();
    filterCalls++;
    filterQueries.add((slug: categorySlug, order: order, page: page));
    if (emptyAfterFirstPage && page > 1) {
      return JmSearchPage(
        query: '',
        total: 0,
        content: const <JmAlbumSummary>[],
        page: page,
      );
    }
    final base = JmResponseParser.searchPage(Fixtures.filter(), page: page);
    if (categorySlug.isEmpty) return base;
    // 模拟真机服务端行为：只认 slug，数字 id 会被忽略、退回默认榜。
    final categoryId = slugToCategoryId[categorySlug];
    if (categoryId == null) {
      return JmSearchPage(
        query: '',
        total: 0,
        content: const <JmAlbumSummary>[],
        page: page,
      );
    }
    final filtered = base.content
        .where((album) => album.categoryId == categoryId)
        .toList(growable: false);
    return JmSearchPage(
      query: '',
      total: filtered.isEmpty ? 0 : base.total,
      content: filtered,
      page: page,
    );
  }

  @override
  Future<JmSearchPage> search({
    required String query,
    int page = 1,
    AlbumOrder order = AlbumOrder.latestUpdate,
  }) async {
    _throwIfFailing();
    return JmResponseParser.searchPage(
      Fixtures.filter(),
      page: page,
      query: query,
    );
  }
}

/// 解析后的首页数据（repository 测试用）。
List<dynamic> parsePromoteFixture() =>
    JmResponseParser.promote(Fixtures.promote());
