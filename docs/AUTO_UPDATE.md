# 自动更新（GitHub Release）

App 启动时去 <https://github.com/xzxycx123/JMComic-Flutter-Android/releases> 查一次版本，
如果最新 release 的 tag 比当前安装版本大，就弹「检测到新版本」，正文直接就是该 release
的 readme，三个出口：**安装** / **取消**（下次启动还会弹）/ **跳过此版本**。

设置里可以随时关掉自动检查（「设置 → 更新 → 自动检查更新」），也可以手动点「检查新版本」。

---

## 1. 判定规则

| 项 | 规则 |
| :--- | :--- |
| 当前版本 | 优先读 `PackageManager.versionName`（来自 `pubspec.yaml` 的 `version:`），读不到才回落 `AppConfig.appVersion` |
| tag 解析 | 只取 tag 里的「点分数字」：`v0.4.3` / `0.4.0` / `JMComic-v0.4.3` 都解析成 `0.4.3`；段数不同按 0 补齐（`0.3.3.1` > `0.3.3`） |
| 更新条件 | `tag 版本 > 当前版本`，且不是 draft、不是预发布（`-beta` / `-rc` 这类） |
| 跳过 | 「跳过此版本」只记住这一个 tag（`settings.skippedReleaseTag`）；下一个版本出现时照常提醒，设置页可一键恢复提醒 |

版本比较实现在 `lib/data/models/app_version.dart`，用例见 `test/data/app_version_test.dart`。

## 2. 取数：REST API + atom 兜底

`lib/data/sources/github_release_client.dart` 按顺序试两路：

1. **REST API** `GET /repos/{owner}/{repo}/releases?per_page=30`
   有 Markdown 正文和 `assets`（APK 名字 / 直链 / 大小）。未鉴权时限流很紧
   （60 次/小时/IP），本机实测经常直接 403。
2. **atom** `GET /releases.atom`
   GitHub 不限制，正文是 HTML（用 `html` 包解析成同一套 block），但**没有附件信息**。

发布正文统一归一成 `ReleaseNotes`（标题 / 段落 / 列表 / 引用 / 代码 / 表格），
两套皮肤共用 `lib/features/update/widgets/release_notes_view.dart` 渲染。

### atom 情况下怎么装包

`GET /releases/expanded_assets/<tag>` 是 release 页附件面板的懒加载片段，里面就有
`.../releases/download/<tag>/JMComic-x.y.z-release.apk`。点「安装」时按需读一次，
拿到直链再下载；连这个也拿不到就退回「用浏览器打开发布页」。

## 3. 安装流程

```
弹窗选「安装」
  -> resolveApk()       REST 的 assets，或 expanded_assets 面板
  -> 下载到 <cache>/jm-update/（进度弹窗，可取消；取消即 CancelToken 中止）
  -> OpenFilex 拉起系统安装器
     失败 -> 打开 release 页兜底
```

- 需要 `REQUEST_INSTALL_PACKAGES` 权限（已加在 `AndroidManifest.xml`），
  首次安装系统会问「允许安装未知来源应用」。
- 安装器由 `open_filex` 经 FileProvider 拉起，安装包放在 app cache 目录，
  不需要存储权限。
- 临时包可以随时清：「设置 → 存储 → 清理临时文件」会顺带删掉 `jm-update/`。

## 4. 触发时机

`lib/features/update/update_gate.dart` 挂在 shell 上，**首帧之后**跑一次检查
（`addPostFrameCallback`），弹窗需要 Navigator 所以不能放在 `MaterialApp.builder`。
`UpdateCheckNotifier` 自己记「本进程已查过」，切皮肤 / 重建 shell 不会重复弹。

## 5. 两套皮肤

| 皮肤 | 弹窗 | 选项 |
| :--- | :--- | :--- |
| Metal | `AlertDialog` | 安装（FilledButton）/ 取消 / 跳过此版本 |
| LiquidGlass | `GlassDialog`（premium 档 platter） | 同一个 `AppDialog` 抽象：`GlassDialogAction`，安装为 primary |

两条路径都走 `AppDialog.show`（`lib/core/ui/glass/app_dialog.dart`），所以
「检测到新版本」只有一个实现。用例 `test/features/update_dialog_test.dart`
对两种皮肤各跑一遍：标题 / release 正文 / 三个选项 / 返回值。

## 6. 发版怎么说才不打扰用户

- 版本号来自 `pubspec.yaml` 的 `version:`（`versionName`），**发版前先改它**，
  否则老版本装上后仍然认为自己是旧版本，会一直被提醒。
- tag 用 `vX.Y.Z`（`tools/publish_release.ps1 -Tag vX.Y.Z`）。
- Release 正文就是弹窗里显示的 readme，写人话：标题 + 分类小标题 + `-` 列表即可
  （表格会被拍平成「单元格 · 单元格」的条目）。
- 预发布（tag 带 `-beta`）不会推给普通用户。

## 7. 校验

```powershell
flutter analyze
flutter test                                                   # 含版本比较 / 正文解析 / 两套皮肤弹窗
pwsh -File tools/check_ui_rules.ps1                             # 无 emoji / 无 Icons.*
flutter test --dart-define=JM_LIVE=true test/manual/release_live_test.dart   # 实网取一次 release + APK 直链
```
