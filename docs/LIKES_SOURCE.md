# 首页点赞量（喜歡数）数据源修复

> 对应版本：0.4.2 之后（`git log` 里 0.4.2 的「主页作品点赞量显示（存在问题）」）
> 相关代码：`lib/features/home/home_likes.dart`、`lib/data/sources/jm_api_client.dart`

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

1. `JmApi.fetchAlbumLikes(albumId)`：请求 `/album`，只解析 `likes`（`JmResponseParser.albumLikes`），
   不构造章节、不做 series 重定向，单本一次轻量请求。
2. `AlbumRepository.likes(albumId)`：仓储层透传。
3. `AlbumLikesNotifier`（`albumLikesProvider`）：
   - 卡片 `build` 时 `ensure([id])`：Sliver 只会构建可视区附近的卡片，等于「露出来才补数」；
   - 同一 id 只请求一次，成功后会话内缓存；结果写进 `state.likes`；
   - 并发上限 4（`maxConcurrent`），失败最多试 2 次（`maxAttempts`），用尽后标记 `failed`，卡片保持 `--`；
   - 只在本卡计数变化时重建（`select`），不会整页刷新。
4. 首页网格 / 横滑分节、搜索结果、收藏页统一换成 `LikesAlbumCard`；
   旧的网页抓取器 `jm_likes_scraper.dart` 与 `ensurePage` / `ensureSearch` 已删除。

真实 0 赞的卡片仍然显示 `--`（与详情页统计条一致），不做「0 占位」以免和「还没取到」混淆。

## 测试

离线（`flutter test`）：

- `test/data/jm_api_client_test.dart`：`fetchAlbumLikes` 读 `/album.likes`、字符串计数、缺字段按 0；
- `test/features/home/home_likes_test.dart`：
  - 同一 id 只请求一次；并发上限 4；失败一次后下次 `ensure` 重试成功；连续失败达到上限后放弃；
  - 真实 0 会进 state；`withResolvedLikes` 不会被 0 覆盖详情页的正数；
  - 首页卡片（横滑 + 网格）渲染 JmAPI 返回值。
- `test/features/search/search_likes_test.dart`：搜索结果卡片用 JmAPI 计数渲染。

实网对比（默认跳过，按需开启）：

```powershell
flutter test --dart-define=JM_LIVE=true --dart-define=JM_PROXY=http://127.0.0.1:7890 `
  test/manual/likes_live_test.dart
```

用例对「最新更新」和「人气推荐」各取前几本，逐本比较：

- 首页路径：`fetchAlbumLikes(id)`（卡片走的就是这条）
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
