# 首页卡片补数：点赞量 + 作品标签

> 对应版本：0.4.2 之后（`git log` 里 0.4.2 的「主页作品点赞量显示（存在问题）」），
> 2026-11-22 起同一次请求顺带补作品标签（封面左上角）。
> 相关代码：`lib/features/home/home_likes.dart`、`lib/features/home/widgets/album_card.dart`、`lib/data/sources/jm_api_client.dart`

## 现象

首页卡片左下角的点赞量显示不正确：几百上千的数字变成一位数（例如 21K 显示成 21），
与点进详情页看到的「喜欢」数对不上；有的卡片干脆只剩 `--`。

## 根因

列表接口（`/promote`、`/latest`、`/categories/filter`、`/search`）**不带点赞数**，
0.4.2 的做法是去抓官方网页列表页，用正则从下面这段 HTML 里取数字：

```html
<a href="#" id="love_likes_1191867"><i class="glyphicon glyphicon-heart"></i>
  <span id="albim_likes_1191867" class="text-white">21K</span></a>
```

网页给的是**压缩写法**（`21K` / `1.2K` / `1.2万`），旧正则
`id="albim_likes_(\d+)"[^>]*>\s*(\d+)` 只取数字前缀：

| 网页原串 | 旧实现解析 | 真实点赞数 |
| --- | --- | --- |
| `21K` | 21 | 21456 左右 |
| `1.2K` | 1 | 1200 左右 |
| `1.2万` | 1 | 12000 左右 |
| `7` | 7 | 7 |

另外网页列表页是 CDN 缓存的，和 APP 详情接口（`/album.likes`）并不总是同一时刻的快照，
个别新本子会出现「列表 2 / 详情 0」这种对不上的情况。

## 修复

点赞量只保留一个数据源：**JmAPI `GET /album?id=` 的 `likes` 字段**，也就是详情页用的同一个值。

1. `JmApi.fetchAlbumMeta(albumId)`：请求 `/album`，只解析 `likes` + `tags`
   （`JmResponseParser.albumMeta`），不构造章节、不做 series 重定向，单本一次轻量请求。
   `fetchAlbumLikes` 是它的便捷包装（只要计数）。
2. `AlbumRepository.meta(albumId)`：仓储层透传。
3. `AlbumMetaNotifier`（`albumMetaProvider`）：
   - 卡片 `build` 时 `ensure([id])`：Sliver 只会构建可视区附近的卡片，等于「露出来才补数」；
   - 同一 id 只请求一次，成功后会话内缓存；结果写进 `state.likes` / `state.tags`；
   - 并发上限 4（`maxConcurrent`），失败最多试 2 次（`maxAttempts`），用尽后标记 `failed`，卡片保持 `--`；
   - 只在本卡数据变化时重建（`select`），不会整页刷新。
4. 首页网格 / 横滑分节、搜索结果、收藏页统一换成 `LikesAlbumCard`；
   旧的网页抓取器 `jm_likes_scraper.dart` 与 `ensurePage` / `ensureSearch` 已删除。

真实 0 赞的卡片仍然显示 `--`（与详情页统计条一致），不做「0 占位」以免和「还没取到」混淆。

## 分类与作品标签（卡片）

列表接口（`/promote`、`/latest`、`/categories/filter`、`/search`）的条目不解析 `tags`，
所以卡片之前只能拿 `category.title` 兜底当标签，于是满屏都是「同人」「單本」。

现在两块信息各归各位：

- **分类**：`JmAlbumSummary.cardCategory`（`category.title`）画在**封面左上角**，单行不截断；
- **作品标签**：`JmAlbumMeta.tags` 来自 `/album.tags`（实测：`泳裝 / 百合 / 扶他 / 巨乳 / 中文 …`），
  画在**作者名下方**，最多 2 个，药丸按内容宽度排版，**不截断、不出省略号**（长了就换行）；
- 语言 / 翻译类（`中文` / `漢化` / `日語` / `英文` …）不占标签位；
  实测 `美漫 / 全彩 / 扶他 / 中文` → 作者名下显示 `美漫` `全彩`；
- 标签跟点赞数共用同一次 `/album` 请求，不额外打网络；拿不到 tags 时作者名下留空；
- 调用方自带 `caption` 时（搜索页自己画标签）不再重复画一遍。

## 测试

离线（`flutter test`）：

- `test/data/jm_api_client_test.dart`：`fetchAlbumMeta` 读 `/album.likes + tags`、字符串计数、缺字段按 0；
- `test/features/home/home_likes_test.dart`：
  - 同一 id 只请求一次；并发上限 4；失败一次后下次 `ensure` 重试成功；连续失败达到上限后放弃；
  - 真实 0 会进 state；`withResolvedMeta` 不会被 0 覆盖详情页的正数，空标签不覆盖已有标签；
  - 首页卡片（横滑 + 网格）渲染 JmAPI 返回值，并在封面左上角显示 `扶她` / `全彩`；
- `test/features/home/home_album_card_test.dart`：标签在封面左上角、语言标签让位、分类名不兜底；
- `test/features/search/search_likes_test.dart`：搜索结果卡片用 JmAPI 计数渲染。

实网对比（默认跳过，按需开启）：

```powershell
flutter test --dart-define=JM_LIVE=true --dart-define=JM_PROXY=http://127.0.0.1:7890 `
  test/manual/likes_live_test.dart
```

用例对「最新更新」和「人气推荐」各取前几本，逐本比较：

- 首页路径：`fetchAlbumMeta(id).likes`（卡片走的就是这条；`fetchAlbumLikes(id)` 等价）
- 详情路径：`getAlbum(id).likes`

要求两边**完全相等**，并覆盖上千 / 上百万的大数。

实测（2026-11-22，`www.cdnutc.cc`，本机代理偶有握手抖动，网络异常的那本会被跳过）：

```
JM1492302  首页=0        详情=0        ok
JM1492301  首页=0        详情=0        ok
JM1492300  首页=0        详情=0        ok
JM1492299  首页=0        详情=0        ok
JM1114751  首页=1542917  详情=1542917  ok
JM1114752  首页=799420   详情=799420   ok
JM145504   首页=349106   详情=349106   ok
```

上千、上百万的原值都逐位相等 —— 旧实现会把 1542917 显示成「154万」、把 21K 显示成 21。

## 备注

- 慢线路上单次 `/album` 可能要 10s 以上，实网用例通过
  `JmApiClient(attemptTimeout: Duration(seconds: 40))` 放宽单次尝试预算；
  App 内仍用默认 9s，靠线路轮换保证首屏速度。
- 每本一次请求，但只有卡片真正露出来才会发生；一屏大约 6~10 本，滚动时自然补齐。
