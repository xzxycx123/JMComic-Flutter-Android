/// 全局可调参数（并发、分页、缓存、图片上限）。
abstract final class AppConfig {
  /// 应用展示名 / 关于页版本前缀，实际版本号来自 pubspec（运行时优先读
  /// `PackageManager.versionName`，见 `UpdateRepository.resolveInstalledVersion`）。
  static const String appName = 'JMComic';
  static const String appVersion = '0.4.6';

  /// 自动更新：发布页与取数地址（只用这一个仓库，见 docs/AUTO_UPDATE.md）。
  static const String releaseOwner = 'xzxycx123';
  static const String releaseRepo = 'JMComic-Flutter-Android';
  static const String releasesPageUrl =
      'https://github.com/$releaseOwner/$releaseRepo/releases';
  static const String releasesApiUrl =
      'https://api.github.com/repos/$releaseOwner/$releaseRepo/releases';
  static const String releasesAtomUrl =
      'https://github.com/$releaseOwner/$releaseRepo/releases.atom';

  /// 版权与许可证（关于页展示；仓库根 LICENSE 为全文，assets/licenses 里是同一份）。
  static const String copyright = 'Copyright (C) 2026 xzxycx';
  static const String licenseName = 'GNU General Public License v3.0';
  static const String licenseAsset = 'assets/licenses/GPL-3.0.txt';
  static const String licenseSummary =
      '本程序是自由软件：你可以依据自由软件基金会发布的 GNU 通用公共许可证第 3 版'
      '（或你选择的任何更新版本）条款重新发布和/或修改它。本程序按「现状」提供，'
      '不附带任何担保；详见随包附带的 GPL-3.0 全文。';

  /// 下载队列级并发上限（对齐 JmScript/DownloadSlots.MAX_PARALLEL_TASKS）。
  static const int maxParallelTasks = 3;

  /// 单任务内的页面并发（对齐 JmScript/JmDownloadWorker.MAX_PARALLEL_IMAGES）。
  static const int maxParallelImages = 3;

  /// 列表接口页大小（/latest 与 /categories/filter 实测每页 80）。
  static const int pageSize = 80;

  /// 首页 feed 缓存有效期。
  static const Duration feedCacheTtl = Duration(minutes: 30);

  /// 分类标签页（内存缓存）有效期：这段时间内切回来直接出缓存、不打网络。
  static const Duration categoryCacheTtl = Duration(minutes: 5);

  /// 首屏出来后空闲预热几个分类（每个只发 1 次 `/categories/filter`）。
  static const int homePrewarmCategories = 3;

  /// 预热请求间隔（错开首屏并发，也避开风控）。
  static const Duration homePrewarmSpacing = Duration(milliseconds: 700);

  /// 触底加载阈值（scrollController.offset > maxScrollExtent - 500）。
  static const double loadMoreThreshold = 500;

  /// 服务端 total 上限（实测 10000，视为服务端计数上限）。
  static const int maxServerTotal = 10000;

  /// PDF 页面长边上限（对齐 JmScript/PdfExporter.MAX_PAGE_EDGE）。
  static const double maxPageEdge = 14400;

  /// 阅读器预取窗口：当前页之前 2 页、之后 5 页（进入阅读器后连续补齐，不再一页一停）。
  static const int readerPreloadBehind = 2;
  static const int readerPreloadAhead = 5;

  /// 阅读器页面加载并发（网络 + 解码；3 路能跟上滑动，又不会把长图解码打满）。
  static const int readerFetchConcurrency = 3;

  /// 阅读器已解码页 LRU 上限。
  static const int readerCacheSize = 14;

  /// 阅读进度落盘节流。
  static const Duration progressWriteThrottle = Duration(seconds: 1);

  /// 下载记录落盘节流（对齐 JmScript/HISTORY_WRITE_INTERVAL）。
  static const Duration historyWriteThrottle = Duration(milliseconds: 500);

  /// 任务级 IO 重试次数（对齐 JmScript/MAX_RETRIES）。
  static const int maxIoRetries = 2;

  /// 单页失败多少条判定整个任务失败。
  static const int maxFailedPages = 3;

  /// 搜索历史上限。
  static const int maxSearchHistory = 10;

  /// 下载记录上限（对齐 JmScript/HistoryStore.MAX_RECORDS）。
  static const int maxDownloadRecords = 200;

  /// 是否输出调试日志。
  static const bool verboseLog =
      bool.fromEnvironment('JM_VERBOSE', defaultValue: false);
}
