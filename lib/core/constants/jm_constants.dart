/// JM 移动端协议常量（2026-11-14 实测，见 docs/PROBE_RESULT_2026-11-14.txt）。
///
/// 与 `JmScript/data/JmApiClient.kt`、`JmScript/data/JmCrypto.kt` 保持一致。
abstract final class JmConstants {
  // ---------------------------------------------------------------- 密钥
  /// 普通接口 token 与 data 解密密钥。
  static const String tokenSecret = '185Hcomic3PAPP7R';

  /// `/chapter_view_template` 专用 token 密钥。
  static const String scrambleTokenSecret = '18comicAPPContent';

  /// data 解密密钥（与 [tokenSecret] 同值，语义上分开命名）。
  static const String dataSecret = '185Hcomic3PAPP7R';

  /// 域名发现服务解密密钥（ts 为空串）。
  static const String domainServerSecret = 'diosfjckwpqpdfjkvnqQjsik';

  // ---------------------------------------------------------------- 版本与 UA
  /// `/setting` 拿不到 jm3_version 时的兜底版本。
  static const String fallbackAppVersion = '2.1.13';

  static const String userAgent =
      'Mozilla/5.0 (Linux; Android 9; V1938CT Build/PQ3A.190705.11211812; wv) '
      'AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/91.0.4472.114 '
      'Mobile Safari/537.36';

  // ---------------------------------------------------------------- 线路
  /// 内置 API 域名兜底表（顺序 = 2026-11-15 实测延迟升序；末位为历史线路）。
  ///
  /// 只是「没有 assets/data/jm_hosts.json 时」的最后兜底：
  /// 正常冷启动会先读内置种子、再按 Health 排序，不再依赖这里的顺序。
  static const List<String> defaultApiHosts = <String>[
    'www.cdnutc.cc',
    'www.cdngwc.net',
    'www.cdngwc.cc',
    'www.cdngwc.club',
    'www.cdnbtd.cc',
    'www.cdnhjk.net',
    'www.cdnutc.me',
  ];

  /// 内置图床兜底表（/setting.img_host 拿不到时使用）。
  static const List<String> defaultImageHosts = <String>[
    'cdn-msp.jmapiproxy2.cc',
    'cdn-msp3.jmapiproxy2.cc',
    'cdn-msp2.jmapiproxy2.cc',
    'cdn-msp.jmapiproxy1.cc',
    'cdn-msp.jmapinodeudzn.net',
    'cdn-msp3.jmapinodeudzn.net',
  ];

  /// 国内（大陆）可用地址：来自发布页「內地 / 分流1 / 分流2」。
  ///
  /// 这三个域名不提供 APP 接口（`/setting` 404，网站被 Cloudflare 挑战挡住），
  /// 但 `/media/albums/...`、`/media/photos/...` 能直出图片 —— 作为**图床兜底**，
  /// 专治海外 CDN 被墙 / 图床全挂时「封面与正文图都加载不出来」。
  static const List<String> domesticHosts = <String>[
    'comic18j-susu.com',
    'comic18j-nico.work',
    'comic18j-neo.com',
  ];

  /// 发布页上的国际 / 东南亚网页域名（HTML 兜底抓取用）。
  static const List<String> overseasWebHosts = <String>[
    '18comic.ink',
    '18comic.vip',
    'jmcomic-zzz.one',
    'jmcomic-zzz.org',
  ];

  /// 全部网页域名（海外在前、国内在后；HTML 兜底按此顺序尝试）。
  static const List<String> webHosts = <String>[
    ...overseasWebHosts,
    ...domesticHosts,
  ];

  /// 域名发现服务（三个 TOS 源，并发请求，谁先给出结果用谁）。
  static const List<String> domainServerUrls = <String>[
    'https://rup4a04-c01.tos-ap-southeast-1.bytepluses.com/newsvr-2025.txt',
    'https://rup4a04-c02.tos-cn-hongkong.bytepluses.com/newsvr-2025.txt',
    'https://rup4a04-c03.tos-cn-beijing.bytepluses.com.cn/newsvr-2025.txt',
  ];

  /// 发布页（国内域名就是从这两页的「內地 / 分流」栏里抓的，互为镜像）。
  static const List<String> publicationUrls = <String>[
    'https://jmcomictt.site/',
    'https://jmcomicgo.org/',
  ];

  /// TOS `jm3_Server` 下发的分流标签（2026-11-15 实测，就是 App 里的「1/2/3/4 分流」）。
  ///
  /// 阅读器顶栏的「线路」菜单按这个表显示；没收录的域名退化成主机名。
  static const Map<String, String> lineLabels = <String, String>{
    'www.cdnbtd.cc': '线路1',
    'www.cdnutc.cc': '线路2',
    'www.cdngwc.net': '线路3',
    'www.cdngwc.club': '线路4',
    'www.cdnutc.me': '线路5',
  };

  static String lineLabelOf(String host) {
    final label = lineLabels[host];
    if (label != null) return label;
    return host.isEmpty ? '线路' : host;
  }

  /// 分流排序：已收录的线路 1..5 按顺序在前，其余（新发现/手填）排后面。
  static int lineRankOf(String host) {
    final index = lineLabels.keys.toList(growable: false).indexOf(host);
    return index < 0 ? 99 : index;
  }

  /// 开源项目的线路清单（GitHub raw，作为域名服务全挂时的旁路）。
  static const List<String> domainMirrorUrls = <String>[
    'https://raw.githubusercontent.com/hect0x7/JMComic-Crawler-Python/master/src/jmcomic/jm_config.py',
  ];

  // ---------------------------------------------------------------- 连通性探测
  /// 打包进 APK 的线路种子（`tools/probe_hosts.ps1` 生成，含最近一次实测状态）。
  static const String hostSeedAsset = 'assets/data/jm_hosts.json';

  /// API 连通性探测端点：必须能拿回 `code=200` + 可解密 + `jm3_version`/`img_host`。
  static const String probeSettingPath = '/setting';

  /// 图床探测用的车号（封面 86KB，能区分「真图」与「HTML 错误页」）。
  static const String probeAlbumId = '1490702';

  /// 单台主机的探测预算；超过就判 timeout 并进冷却。
  static const Duration probeTimeout = Duration(seconds: 5);

  /// 业务请求单次尝试预算（旧实现用全局 15s+35s，首屏要等分钟级）。
  static const Duration requestAttemptTimeout = Duration(seconds: 9);

  /// 单个业务请求的总预算：轮换线路到点就停，避免「7 台死线路 × 9s」把首屏拖到分钟级。
  static const Duration requestTotalBudget = Duration(seconds: 24);

  /// 图片下载的总预算（单页最大，超过就交给下载引擎重试）。
  static const Duration imageTotalBudget = Duration(seconds: 40);

  /// 失败主机冷却窗口：窗口内排到最后，避免每次点击都重撞同一台死线路。
  static const Duration hostCooldown = Duration(minutes: 10);

  /// 健康记录有效期：窗口内不再重复探测，直接用上次结果排序。
  static const Duration healthTtl = Duration(minutes: 30);

  // ---------------------------------------------------------------- 请求头
  static const String tokenHeader = 'token';
  static const String tokenParamHeader = 'tokenparam';
  static const String requestedWith = 'com.JMComic3.app';

  /// 图片请求 Accept（缺一可能 403 或返回 HTML）。
  static const String imageAccept =
      'image/avif,image/webp,image/apng,image/*,*/*;q=0.8';

  // ---------------------------------------------------------------- 图片
  /// `/chapter_view_template` 未匹配到 scramble_id 时的兜底阈值（对齐 ImageScrambler.DEFAULT_SCRAMBLE_ID）。
  static const int defaultScrambleId = 220980;

  /// `var scramble_id = 220980;` 提取正则。
  static const String scrambleIdPattern = r'var\s+scramble_id\s*=\s*(\d+)\s*;';

  // ---------------------------------------------------------------- 签到（实测 2026-11-21）
  /// `GET /daily?user_id=<uid>`：当月签到记录（`daily_id` + `record`）。
  static const String dailyPath = '/daily';

  /// `POST /daily_chk`（form `user_id` + `daily_id`）：服务端签到，发 JCoin。
  static const String dailyCheckInPath = '/daily_chk';

  // ---------------------------------------------------------------- 目录
  /// 公共 Documents 下的导出目录。
  static const String exportDirName = 'JMComics';

  /// MediaStore RELATIVE_PATH。
  static const String exportRelativePath = 'Documents/JMComics/';
}

/// `/categories/filter` 与 `/search` 的 `o` 参数（实测均返回 200，total 有差异）。
enum AlbumOrder {
  latestUpdate('mr', '最新更新'),
  mostViewed('mv', '最多观看'),
  monthly('mv_m', '月榜'),
  weekly('mv_w', '周榜'),
  daily('mv_t', '日榜'),
  newest('md', '最新上架'),
  popular('mp', '人气推荐');

  const AlbumOrder(this.code, this.label);

  /// 服务端参数值。
  final String code;

  /// UI 文案。
  final String label;

  static AlbumOrder fromCode(String? code) {
    for (final order in AlbumOrder.values) {
      if (order.code == code) return order;
    }
    return AlbumOrder.latestUpdate;
  }
}

/// 顶层分类的固定兜底表（/categories 请求失败时用；id 与实测一致）。
class JmCategoryFallback {
  const JmCategoryFallback(this.id, this.name);

  final String id;
  final String name;

  static const List<JmCategoryFallback> items = <JmCategoryFallback>[
    JmCategoryFallback('0', '最新A漫'),
    JmCategoryFallback('1', '同人'),
    JmCategoryFallback('2', '單本'),
    JmCategoryFallback('3', '短篇'),
    JmCategoryFallback('4', '其他類'),
    JmCategoryFallback('5', '韓漫'),
    JmCategoryFallback('6', 'English Manga'),
    JmCategoryFallback('7', 'Cosplay'),
    JmCategoryFallback('8', '3D'),
    JmCategoryFallback('9', '禁漫漢化組'),
  ];
}
