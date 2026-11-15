/// 全局可调参数（并发、分页、缓存、图片上限）。
abstract final class AppConfig {
  /// 应用展示名 / 关于页版本前缀，实际版本号来自 pubspec（package_info 未接入时用此常量）。
  static const String appName = 'JMComic';
  static const String appVersion = '0.1.0';

  /// 下载队列级并发上限（对齐 JmScript/DownloadSlots.MAX_PARALLEL_TASKS）。
  static const int maxParallelTasks = 3;

  /// 单任务内的页面并发（对齐 JmScript/JmDownloadWorker.MAX_PARALLEL_IMAGES）。
  static const int maxParallelImages = 3;

  /// 列表接口页大小（/latest 与 /categories/filter 实测每页 80）。
  static const int pageSize = 80;

  /// 首页 feed 缓存有效期。
  static const Duration feedCacheTtl = Duration(minutes: 30);

  /// 触底加载阈值（scrollController.offset > maxScrollExtent - 500）。
  static const double loadMoreThreshold = 500;

  /// 服务端 total 上限（实测 10000，视为服务端计数上限）。
  static const int maxServerTotal = 10000;

  /// PDF 页面长边上限（对齐 JmScript/PdfExporter.MAX_PAGE_EDGE）。
  static const double maxPageEdge = 14400;

  /// 阅读器预加载半径（±2 页）。
  static const int readerPreloadRadius = 2;

  /// 阅读器已解码页 LRU 上限。
  static const int readerCacheSize = 12;

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
  static const bool verboseLog = bool.fromEnvironment('JM_VERBOSE', defaultValue: false);
}
