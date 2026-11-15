# JMComic 0.3.0 发布说明

> 版本：`0.3.0+4` · 平台：Android 8.0+（minSdk 29） · 产物：`JMComic-0.3.0-release.apk`
> 上一版：`0.2.0+3`

## 新功能

- **点赞**：详情页「点赞」按钮（爱心），登录后可用；服务端 `/like` 不回计数，客户端乐观 +1，已赞后锁定不可取消。
- **评论区**：详情页章节下方新增评论区 —— 先铺 5 条、可展开全部、可加载更多；支持写评论与回复，带「含剧透」标记与相对时间。
- **登录体验**：
  - 登录失败改为对话框（图标 + 原因 + 排查提示 + 重试），原因归一到「密码错 / 限流 / 人机校验 / 线路异常」；
  - **登录成功自动做一次收藏双向同步**：先把云端收藏拉回本地，再把本地收藏推到云端，结果在成功框里给出「云端 N · 拉回 M · 上传 K」。
- **首页标签页缓存**：分类/排序切换不再整页重载 —— 命中内存缓存立刻出内容，超过 5 分钟才后台静默刷新；首屏出来后空闲预热 3 个分类（每类只发 1 次请求）。
- **阅读器手势**：左右翻页与上下滚动**两种模式都支持双指缩放（最高 4×）与双击放大**，缩放时自动锁住翻页/滚动，缩回 1.0 归位。
- **翻页动画开关生效**：设置里关掉「翻页动画」后，点屏/拖进度条跳页改为瞬切（不再一律 240ms 动画）。

## 改进

- 收藏图标由书签改为**五角星**（描边未收藏 / 实心已收藏），与点赞的爱心区分开。
- 首页 AppBar 品牌标记改用 `img/brand/brand.png` 左侧切出的方形 mark（`brand_logo.png`）。
- 详情页统计条把误标的「收藏」改成「喜欢」（对应 `/album.likes`）。
- 「我的」页新增「同步收藏」行（同步中 / 上次失败 / 云端 N 本），收藏页同步按钮与全局同步状态共用一份，避免并发对账。
- 401 在请求层统一归一为「登录状态已失效，请重新登录」，不再被当成线路故障去轮换域名。
- README 截图换成真机原图（`ref img/`）。

## 修复

- 点分类标签每次都重新打 4 个接口、闪骨架屏、滚动位置丢失。
- 「翻页动画」开关无实际效果。
- 上下滚动模式无法缩放，左右翻页模式缩放后仍会误翻页。
- 登录失败只有输入框下一行小字，信息量与可操作性都不够。

## 协议（本次实测新增）

| 能力 | 端点 | 说明 |
|---|---|---|
| 点赞 | `POST /like`（multipart `id`） | 明文 `{code,msg,status}`，无计数、无取消 |
| 评论列表 | `GET /forum?page&aid&mode=manhua` | 游客可读，`total` 为字符串 |
| 发评论 | `POST /comment`（`comment/aid/status/comment_id`） | 需登录；`status=1` 为剧透 |

详见 `docs/INTERACTION.md`；复核脚本 `tools/probe_interact.ps1`、`tools/probe_forum.ps1`。

## 升级提示

- 收藏数据结构未变（0.2.0 的 per-album 账本继续可用），无需迁移。
- 0.2.0 的用户名/密码没有被保存过，升级后仍只需重新登录一次（cookie 若仍有效则自动恢复）。
- 已知限制：点赞不可取消；评论不支持点赞/删除/举报（接口未验证）。

## 下载与安装

| 项 | 值 |
|---|---|
| 产物 | `JMComic-0.3.0-release.apk`（63.4 MB） |
| 包名 / 版本 | `com.jmcomic.jm_comic` · versionName `0.3.0` · versionCode `4` |
| minSdk / targetSdk | 29（Android 8.0） / 35 |
| SHA256 | `756c2330fad389065ec80c24e36b11df34ffd0cfbf4afbdcb4f1c0692a5805fe` |

```bash
adb install -r JMComic-0.3.0-release.apk    # 覆盖安装；必要时 adb uninstall com.jmcomic.jm_comic
```

APK 使用 debug keystore 签名，仅自用 / 侧载，不上架应用商店。

## 构建与校验

```powershell
flutter analyze      # 0 issue
flutter test         # 140 passed / 2 skipped（实网用例需 JM_LIVE=true）
pwsh -File tools/check_ui_rules.ps1   # UI 守卫通过（无 emoji / 无 Icons.*）
flutter build apk --release
```
