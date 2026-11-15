# 互动：点赞与评论（0.3.0 已验证实现）

> 本文是「详情页能点赞、能看评论、能发评论」的落地契约。协议部分是 2026-11-15 用
> `tools/probe_interact.ps1` / `tools/probe_forum.ps1` 实网打出来的，不是猜的。
> 收藏与会话见 `docs/FAVORITES.md`，字段全集见 `Plan/PLAN.md` §5.4。

---

## 0. 速览

| 能力 | 端点 | 登录 | 客户端行为 |
|---|---|---|---|
| 点赞 | `POST /like`（multipart `id`） | **要**（服务端对游客也返回 success，但产品上要求登录） | 乐观 +1、锁成「已点赞」、无取消 |
| 评论列表 | `GET /forum?page&aid&mode=manhua` | 不要（游客可读） | 每页 20，先铺 5 条，展开/加载更多 |
| 发评论 | `POST /comment`（multipart） | **要**（未登录 401） | 面板提交 → 回第 1 页 → toast 服务端文案 |
| 回复 | `POST /comment` + `comment_id` | **要** | 同一条面板，标题变「回复评论」 |

---

## 1. 实测记录（2026-11-15，线路 `www.cdnutc.cc`）

### 1.1 点赞

```
POST /like
Body(multipart): id=1490702
→ {"code":200,"data":"<AES>"}
解密后: {"msg":"評價成功!","status":"success","code":200}
```

要点：

- 参数名是 **`id`**（用 `aid` 会 400）；
- 解密后的对象自带 `code/msg/status`，**没有计数字段**，所以客户端必须乐观 +1；
- 同一本重复点赞不再叠加（实测两次都是 172），因此产品上按「一次性点赞」处理，不提供取消；
- 状态来源：`GET /album` 的 `liked`（布尔）与 `likes`（「喜歡」数）。

### 1.2 评论列表

```
GET /forum?page=1&aid=1490702&mode=manhua
解密后: {"list":[],"total":"0"}
```

- 未登录可读（这一点与网页版不同，别被「未登录就该 401」的直觉骗了）；
- `total` 是**字符串**，要 `asInt`；
- 空评论本就返回 `{"list":[],"total":"0"}`，不是错误。

条目字段（对齐 jm-mobile `CommentListResponse.ListItem`）：

```json
{
  "AID": "1490702", "BID": null, "CID": "12345", "UID": "67890",
  "username": "abc", "nickname": "阿B", "likes": "3",
  "addtime": "1794625636", "parent_CID": "0",
  "content": "好看", "photo": "/media/users/xxx.jpg",
  "spoiler": "0", "replys": [ /* 同构，可为 null */ ]
}
```

### 1.3 发评论

```
POST /comment
Body(multipart): comment=<正文>, aid=<专辑 id>, status=<1 剧透 | 0 正常>, comment_id=<父评论 id，可省>
→ 解密后: {"msg":"評論成功!","status":"ok","aid":1490702,"cid":9001,"spoiler":"0"}
未登录 → HTTP 401
```

`status` 的语义照抄 jm-mobile（`// TODO 是否剧透`）：我们落成「含剧透」开关，`1` = 剧透。

---

## 2. 客户端实现映射

| 层 | 文件 | 关键点 |
|---|---|---|
| 模型 | `lib/data/models/jm_comment.dart` | `JmComment` / `JmCommentPage`；`addtime` 兼容秒级时间戳与 `yyyy-MM-dd HH:mm:ss`；`displayTime` 出「刚刚 / N 分钟前 / N 小时前 / N 天前 / MM-DD」；`initial` 取昵称首字（`runes.first`，不切坏代理对） |
| 解析 | `lib/data/sources/jm_response_parser.dart` → `comments()` | `list` 逐条过滤空正文；`total` 用 `asInt` |
| API | `lib/data/sources/jm_api_client.dart` → `likeAlbum` / `fetchComments` / `postComment` | `/like` 校验 `status=success` 与内层 `code`；`/comment` 校验 `status=ok`；**401 在 `_requestApiOnHost` 统一归一**成 `JmContentException('登录状态已失效，请重新登录')` |
| 仓储 | `lib/data/repositories/album_repository.dart` | `like` / `comments` / `postComment` 三个薄封装 |
| 状态 | `lib/features/album/album_providers.dart` | `albumLikeProvider`（FamilyNotifier，`build` 用 `ref.read` 取详情初值，**不 watch**，否则详情刷新会把刚点的赞覆盖回去）；`albumCommentsProvider`（FamilyAsyncNotifier，`refresh` / `loadMore` / `post`） |
| UI | `lib/features/album/album_page.dart`（动作条）+ `widgets/comment_section.dart` | 点赞/评论两颗胶囊按钮；评论区 5 条预览 → 展开 → 加载更多；`_ComposerSheet` 写评论（500 字 + 含剧透开关） |

### 2.1 点赞状态机

```
[idle] --tap(未登录)--> 弹「登录后才能操作」→ /login
[idle] --tap(已登录)--> 立刻 liked=true, likes+1（前台成功，不转圈）
   ├─ 后台成功 --> 保持已赞（无取消）
   └─ 后台失败 --> 回滚 liked=false, likes-1 + SnackBar「点赞失败：…」，可再点
```

### 2.2 评论列表状态机

```
build   --> GET /forum page=1  (loading → data)
展开     --> preview(5) → 全部（本地，不发请求）
加载更多 --> page+1 追加，按 CID 去重；返回空页即 hasMore=false
发送     --> 立刻关面板：列表顶部插入 pending 条目（「发送中」标记）+ total+1
   ├─ 后台成功 --> 只摘掉 pending 标记（不整页刷新，避免服务端未收录时评论凭空消失）
   └─ 后台失败 --> 撤回该条 + total-1 + SnackBar「发送失败：…」
```

> 0.3.1 起点赞与发评论都是「前台先成功、后台发」：用户不转圈等待，失败才回滚。

### 2.3 正文清洗（HTML）

站点评论的 `content` / `nickname` 是富文本，实测会带 `<div>`、`<br>`、`&nbsp;`、`&lt;`：
直接塞进 `Text` 就会看到 `<div></div>`。统一在 `JmComment.fromJson` 里过 `cleanText()`：

1. `<br>` → 换行；`</p|div|li|blockquote>` → 换行（否则 `a<br>b` 会被拼成 `ab`）；
2. `html.parseFragment(...).text` 解析并解码实体（`&nbsp;` → 空格、`&lt;` → `<`）；
3. 逐行 trim、把 3 个以上连续换行压成 2 个。

纯文本无 `<`/`&` 时直接跳过解析，避免无谓开销。

---

## 3. 登录门槛与失败提示

- 点赞 / 写评论 / 回复：`accountSessionProvider.isLoggedIn` 为假时弹 `AlertDialog`（`user.svg` + 「登录后才能操作」+ 「先不登录 / 去登录」），**不静默失败**。
- 401（会话过期）：请求层抛 `JmContentException`，调用方把原因显示在 SnackBar/行内错误里，并把 `AccountSession` 标 `needsLogin`。
- 登录失败本身走 `LoginPage` 的失败对话框（图标 + 原因归一化 + 排查提示 + 「重试」），原因映射在 `AuthRepository.describeLoginFailure()`。
- 登录态持久化策略见 `docs/FAVORITES.md` §4.5（cookie 每次响应回写；只有明确的鉴权失败才降级），0.3.1 起点赞/评论的失败提示与「是否已登录」判断都依赖它。

---

## 4. 视觉与图标（不破 UI 规则）

| 位置 | 图标 | 说明 |
|---|---|---|
| 详情页收藏 | `star.svg` / `star-filled.svg` | **五角星**：描边=未收藏、实心=已收藏（原来是书签，0.3.0 换掉） |
| 详情页点赞 | `heart.svg` / `heart-filled.svg` | 未赞描边、已赞实心 + `primaryContainer` 底 |
| 评论区入口 | `comment.svg` | 「写评论 / 评论 N」胶囊、输入条左侧 |
| 发送 | `send.svg` | 输入条右侧、面板「发送」按钮旁 |
| 评论头像 | 无（`CachedNetworkImage` 或首字圆形占位） | 头像走图床，带 `imageHeaders` |

剧透标签用 `AppTypography.micro` + `error` 色 12% 透明底，不放 emoji（守卫会拦）。

---

## 5. 测试

| # | 用例 | 断言 |
|---|---|---|
| 1 | 未登录点「点赞」 | 弹登录对话框，`likeAlbum` 未被调用 |
| 2 | 已登录点赞成功 | `liked=true`、`likes` +1、按钮文案「已点赞 N」 |
| 3 | 点赞失败（401） | 停在未点赞态、SnackBar 带原因 |
| 4 | 评论首屏 | 只渲染 5 条 + 「查看全部 N 条评论」 |
| 5 | 展开 | 渲染全部条目，不再发请求 |
| 6 | 加载更多 | 第 2 页追加、CID 去重、`hasMore=false` 后按钮消失 |
| 7 | 发评论（0.3.1 乐观） | 面板立即关闭、顶部出现「发送中」条目，后台成功后标记消失 |
| 8 | 发评论失败 | 条目撤回、SnackBar 报原因，可重发 |
| 9 | `addtime` 两种格式 | 都能出相对时间，不抛异常 |
| 10 | 空评论 | 显示「还没有评论，来说两句」，不是错误态 |
| 11 | HTML 正文 | `<div>/<br>/&nbsp;/&lt;` 全部清洗，列表里没有尖括号 |
| 12 | 点赞（0.3.1 乐观） | 点下即「已点赞 N」，无 loading；后台失败才回滚 |

自动化覆盖：`test/helpers/fixtures.dart` 的 `FakeJmApi` 已实现 `likeAlbum` / `fetchComments` / `postComment`（记录 `likedAlbums`、`postedComments`），可直接写 widget 测试。

---

## 6. 不做 / 风险

- **不做**：取消点赞、评论点赞、删评论、举报、@ 提醒、未读通知 —— 接口未验证。
- **不做**：评论富文本 / 图片 / 表情；正文按纯文本渲染。
- 风险：`/forum` 的 `mode` 目前固定 `manhua`（小说区可能是别的值）；`/comment` 的 `status` 语义来自 jm-mobile 注释，若服务端把 `1` 当「审核中」需按实网再校一次。
- 风险：评论是公开内容，展示时必须原样、不加编辑；`photo` 相对路径要拼图床 host（`JmApi.imageHost`）。
