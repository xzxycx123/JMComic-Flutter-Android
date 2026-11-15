# 代码审查（子代理）结论与处置

- 审查对象：`lib/**`、`test/**`、`android/**`，基准 `PLAN.md` 与 `D:\data\coding\JmScript`（只读）
- 审查方式：独立子代理只读审查（12 条），本文件记录逐条处置
- 时间：2026-11-15

## 处置一览

| # | 结论 | 处置 | 落点 |
|---|---|---|---|
| 1 | 首页瀑布流到底后无限请求 | ✅ 已修：`HomeFeed.gridExhausted`，空页即置位；`loadMore` 前置判断；新增用例 | `home_feed.dart`、`home_repository.dart:143`、`home_providers.dart:69`、`home_repository_test.dart` |
| 2 | 引导/首页失败后「重新加载」永远无效 | ✅ 已修：`refresh()` 先 `invalidate(homeRepositoryProvider)`，引导未成功时同时作废 `jmBootstrapProvider`；设置页「重新探测」同步作废仓储 | `home_providers.dart:58`、`settings_page.dart` |
| 3 | 失败页阈值不一致 + 重试误判 | ✅ 已修：失败页 ≥3 即整任务失败（先判失败页再判空页）；`JmApiException(network:false)` 不重试 | `download_worker.dart:152`、`download_coordinator.dart:149` |
| 4 | 取消后任务仍会启动 / 被回写成 running | ✅ 已修：`run()` 入口 `throwIfCancelled()`；coordinator 排队阶段先检查；`_write` 不再覆盖 cancelled；新增「取消 + 临时目录清空」用例 | `download_worker.dart:48,220`、`download_coordinator.dart:135`、`download_flow_test.dart` |
| 5 | 进度节流状态跨任务共享 | ✅ 已修：节流状态改为 `Map<workId, (status, percent, at)>`，任务结束清理 | `download_worker.dart:40,232` |
| 6 | PDF 全量页 + 二次解码的内存峰值 | ◐ 部分修：尺寸读取改为只读 PNG IHDR（不再整图解码一次）；`pw.Document` 仍需整包驻留，记为已知限制 | `image_processor.dart:70`、`pdf_exporter.dart` |
| 7 | 阅读器/下载并发解大图 | ◐ 部分修：阅读器预加载并发限制到 2；下载侧保持 PLAN 的 3 路（与 Kotlin 基准一致） | `reader_page.dart:197` |
| 8 | FallbackPdfSink 一次失败永久降级 | ✅ 已修：不再改写 `_primary`，降级只对本次生效 | `pdf_sink.dart:151` |
| 9 | MediaStore 未校验转正结果 | ✅ 已修：`update() <= 0` 抛 `IOException`，与 `DocumentsPdfStore.kt` 一致；整包字节流式写仍待优化 | `MainActivity.kt:81`、`tools/apply_android_config.ps1` |
| 10 | 域名发现串行、无整体超时 | ✅ 已修：三源并发取首个非空，单源 7s、整体 8s 封顶 | `jm_endpoint_resolver.dart:25` |
| 11 | 取消用例恒过、缺失败页/重试用例 | ✅ 已修：新增 gate 取消用例（断言 cancelled + 临时目录空 + 停止下载）与「失败页 ≥3 → failed」用例 | `test/download/download_flow_test.dart` |
| 12 | 关键交互/缓存覆盖不足 | ◐ 部分修：补了「空页到底」用例与 `assets/*` 的 emoji 守卫；ReaderPage 级点击/进度、Hive TTL 缓存、cookie 下发仍待补 | `test/features/*` |

## 仍未覆盖（明确记录，不假装通过）

1. `ReaderPage` 级交互用例（点右 1/3 → 页码 +1、HUD 3s 自动隐藏、退出写 `progress:`、切模式保持页码）。
2. `HomeRepository` 的 Hive TTL 缓存路径（`readCache()` / 过期 → 后台刷新）只在手测覆盖。
3. `JmApiClient` 的 cookie 下发与「host A 失败 → host B 成功」的线路轮换单测。
4. PDF 导出内存：100 页以上的长本在低端机上仍可能 OOM（`pw.Document` 全量驻留）；后续可换成分页流式写或把 PDF 生成下沉到原生。
5. `requests` 级节流参数（`HISTORY_WRITE_INTERVAL`）没有直接单测，靠行为断言间接覆盖。

## 复核命令

```powershell
$env:Path = 'D:\data\tools\flutter\bin;' + $env:Path
flutter analyze   # No issues found
flutter test      # 78 用例全绿
pwsh -File .\tools\check_ui_rules.ps1
```
