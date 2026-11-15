# 登录与收藏（会话 + 收藏同步）设计

> 适用代码：`lib/data/local/progress_store.dart`（现有 `FavoritesStore`）、`lib/features/album/album_page.dart`、`lib/features/mine/mine_page.dart`。
> 参考实现：`Dedicatus546/jm-mobile`（Kotlin / Compose，GPL-3.0，branch `dev`，2026-11 源码核对）。
> 协议基准：`hect0x7/JMComic-Crawler-Python`。协议事实以 `Plan/PLAN.md` §5 与 `tools/probe_api.ps1` 的实时输出为准。

---

## 0. 一页速览

**登录**是收藏同步的前置条件，两者必须一起设计：没有会话，收藏只能在本地；没有 outbox，登录也不会把历史收藏带上去。

| 主题 | 一句话结论 | 关键约束 |
|---|---|---|
| 会话 | **cookie（含 `AVS`）为主、`/login` 换取账号信息为辅** | 密码只在「记住密码」开启时进系统密钥库；请求头 token 每请求现算 |
| 自动登录 | **cookie 校验 → 失效则用保存的密码静默重登一次**（0.3.2 默认开） | 重登失败才回 `needsLogin`，不循环 |
| 登录后同步 | **登录成功立即双向同步一次**（云端拉回 + 本地补推），0.3.0 已实现 | 失败不阻塞登录，提示框里给统计与「稍后手动同步」 |
| 收藏 | **本地账本 + 服务端镜像**，服务端只镜像「在不在收藏里」 | `POST /favorite` 是 **toggle**，必须反向对账 |
| 收藏图标 | **五角星**（`star` / `star-filled`），点赞是爱心 | 图标语义别混：星=收藏、心=点赞 |
| 文件夹 | v1 **只做本地** | 移动端 `folder_id` 仅固定 0，建夹接口未验证 |
| 上限 | 来自登录响应的 `album_favorites_max` | ≥90% 时告警、超限禁用 |

相关文档：点赞/评论见 **`docs/INTERACTION.md`**（同一套会话与登录门槛）。

三条红线：

1. **写本地、读本地**。收藏页永远先渲染 Hive，网络只做对账/补数据。
2. **服务端只同步布尔**（在不在收藏里）。标题快照、文件夹、追更、角标都是本地能力。
3. **toggle 必须对账**。返回 `type` 与预期不符要反向补发一次，否则会静默删掉用户收藏。

---

## 1. 现状（本仓库代码事实）

| 位置 | 现在是什么 | 结论 |
|---|---|---|
| `lib/data/local/progress_store.dart` → `FavoritesStore` | Hive box `jm_favorites` 存 `{ids:[...]}`，只有 `read/contains/count/toggle/clear` | 只够放 id，收藏页无法离线渲染 → 扩成 per-album 记录 |
| `lib/features/album/album_page.dart:105` | `_toggleFavorite()` + SnackBar「已收藏 / 已取消收藏」 | 骨架对，缺 undo / 文件夹 / 同步标记 |
| `lib/features/mine/mine_page.dart:46` | 统计卡 `favorites.length` | 有数字，没有入口 |
| 全局 | 无 `/login`、无 `/favorite` 调用，无会话层 | v1 纯本地，符合「先能用手」 |
| `lib/data/local/hive_init.dart` | box 已开：`jm_favorites` | 复用；新增 `jm_favorite_folders`、`jm_favorite_outbox`、`jm_session` |
| `lib/core/network/` | `dio_factory` 已有 token 头 + cookie jar | 会话层直接挂在这条链上，不另建客户端 |

---

## 2. `jm-mobile` 的登录是怎么做到的（源码解剖）

### 2.1 网络层：Retrofit + 五个拦截器

`retrofit/Retrofit.kt` 里是唯一客户端，`baseUrl` 故意设为占位符，真实域名在拦截器里换：

```
OkHttpClient
 ├─ InitInterceptor      // 见 2.1.1：非 @GInit 的请求先 await 初始化完成
 ├─ BaseUrlInterceptor   // 动态替换域名（线路轮换）
 ├─ TokenInterceptor     // 加 token / tokenparam 头
 ├─ ToastInterceptor     // 业务错误统一弹 toast
 ├─ DecryptInterceptor   // 解密 {code,data}
 └─ cookieJar            // 持久化 cookie（关键，见 2.3）
```

**2.1.1 初始化闸门**：`@GInit` 标注在 `login` 上；`InitInterceptor` 对带 `@GInit` 的请求**放行**，对其他所有请求先 `await InitManager.deferred`。也就是「登录自己不需要初始化，别的接口必须等初始化做完」。

**2.1.2 token 是进程级常量**（`retrofit/Constant.kt`）：

```kotlin
val API_TS = System.currentTimeMillis() / 1000      // 进程启动时算一次
const val API_VERSION = "1.8.2"
const val API_TOKEN_SECRET = "185Hcomic3PAPP7R"
val API_TOKEN_HASH = md5("${API_TS}${API_TOKEN_SECRET}")
```

→ 整个进程复用同一个 `token`/`tokenparam`，并且版本写死 `1.8.2`（老接口）。

### 2.2 登录时序

```
LoginScreen（用户名/密码输入）
   └─ UserViewModel.login(username, password)          // 置 isLoading
        └─ UserRepository.login → UserService.login     // @GInit @POST("login") @Multipart(username,password)
             └─ ResponseWrapper<LoginResponse>          // DecryptInterceptor 已解密
                  └─ userManager.updateUser(loginResponse.toUser(password))
                       ├─ _userState 更新（isLogin = uid > 0）
                       └─ userStorage.set(user)         // 落盘，含明文密码
LoginScreen 观察 isLogin → navigate(TabRoute("user")) { popUpTo(LoginRoute, inclusive = true) }
```

`LoginResponse` 字段（`retrofit/model/LoginResponse.kt`）：`uid, username, email, photo, coin, album_favorites, level_name, level, nextLevelExp, exp, expPercent, album_favorites_max`。

### 2.3 会话怎么存

两套存储，缺一不可：

| 存储 | 内容 | 时机 |
|---|---|---|
| `UserStorage` | `User(id, username, **password**, avatar, level, …, currentCollectCount, maxCollectCount, jCoin)` | 登录成功后写入；登出时删除 |
| `CookieStorage` | OkHttp `Cookie` 列表（按 `domain:path:name` 去重） | 每次响应 `saveFromResponse` 都写；启动时 `Retrofit.init()` 恢复 |

`Retrofit.init()` 是 `AppInitTask(sort=1)`：从 `CookieStorage` 恢复 cookie 后，后续请求自动带上 —— 这就是「关掉 App 再打开仍是登录态」的真正原因（cookie，而不是密码）。

### 2.4 自动登录：`AppInitTask(sort=4)`

`UserManager.init()`：

```kotlin
data = userStorage.get()                       // 先恢复 UI 上的用户
if (username.isNotEmpty() && password.isNotEmpty()) {
    autoLogin(username, password)              // 再发一次 /login
}
```

即：**每次冷启动都重新登录一次**，用明文密码换新 cookie。好处是会话永不过期；代价是密码必须落盘。

### 2.5 登出

`UserManager.clearUser()`：清内存状态 → `retrofit.clearCookie()` → `userStorage.remove()` → `cookieStorage.remove()`。三处都清，避免「登出后收藏还是别人的」。

### 2.6 登录页 UI 细节（这几条值得照抄）

- 用户名/密码输入框都做 **ASCII-only 过滤**：`InputTransformation { if (!text.matches(Regex("""\A\p{ASCII}*\z"""))) revertAllChanges() }`（避免中文输入法把全角字符塞进去）。
- 用户名 **失焦时 trim**（`onFocusChanged` 里 `replace(0,length,trimmed)` + `placeCursorAtEnd()`）。
- IME：用户名 `Next` → 聚焦密码；密码 `Done` → `clearFocus()` + 直接提交。
- 按钮 loading：`CircularProgressIndicator(size 20) + "登录中"`，`enabled = !isLoading`。
- 进入页面自动聚焦用户名（`FocusRequester.requestFocus()`），成功后 `popUpTo(LoginRoute){inclusive=true}`，登录页不留在返回栈。

### 2.7 它的五个坑（我们逐条改）

| 坑 | 影响 | 我们的做法 |
|---|---|---|
| 明文存密码做自动登录 | 设备被 root / 备份导出即账号失守 | 同样支持自动登录，但密码走 `flutter_secure_storage`（Keystore/Keychain），不落明文 |
| token 用进程启动时的固定 ts + 写死版本 `1.8.2` | 服务端若做时间窗校验会整进程失效；版本落后拿不到新字段 | **每请求现算** `md5(ts+secret)`，版本取 `/setting.jm3_version` |
| 只依赖 `Set-Cookie`，没有显式 `AVS` 处理 | 部分线路下 python 库需要手动补 `AVS = res_data["s"]` | 登录响应里若有 `s`，显式写 `AVS` cookie（见 4.3） |
| 无「会话失效」判定 | 401/重定向时 UI 仍显示已登录，收藏静默失败 | 统一拦截：响应非 JSON / 被重定向 / `code!=200` 且要求登录 → 标 `needsLogin`（见 4.5） |
| 登录与初始化耦合在拦截器里（`runBlocking`） | 冷启动所有请求串行等待 | 用显式 `await SessionReady`，且 `/setting` 与 `/login` 标记为「不等待」 |

---

## 3. 接口契约

### 3.1 登录 / 会话

| # | 用途 | 方法 / 路径 | 参数 | 返回 | 备注 |
|---|---|---|---|---|---|
| 1 | 登录 | `POST /login` | multipart `username`、`password` | `{uid, username, email, photo, coin, album_favorites, level_name, level, nextLevelExp, exp, expPercent, album_favorites_max}` + `Set-Cookie`（含 `s`→`AVS`） | jm-mobile 与 python 库双重验证 |
| 2 | 引导（必须最先） | `GET /setting` | — | `{jm3_version, img_host, …}` + cookie ×5 | 我们已有，登录前后都要能跑 |
| 3 | 会话校验 | `GET /favorite?page=1&o=mr&folder_id=0` | 见 3.2 | 200 且 JSON → 会话有效 | 比新增接口更省事 |
| 4 | 观看历史（可选） | `GET /watch_list` | `page` | 同收藏列表结构 | 已由 jm-mobile 使用 |

`LoginResponse` 里我们真正要用的只有：`uid`、`username`、`photo`（头像）、`album_favorites`（当前收藏数）、`album_favorites_max`（上限）、以及 cookie 里的 `AVS`。

### 3.2 收藏

| # | 用途 | 方法 / 路径 | 参数 | 返回 |
|---|---|---|---|---|
| 5 | 收藏列表 | `GET /favorite` | `page`（1 起）、`o`=`mr`\|`mp`、`folder_id`（默认 0） | `{count, total, list:[{id,author,description,name,image,category{id,title},category_sub}]}` |
| 6 | 收藏/取消 | `POST /favorite` | multipart `aid` | `{msg, status:"ok", type:"add"\|"remove"}`（**toggle**） |
| 7 | 计数校准 | `GET /favorite?page=1&o=mr` | — | 取 `count` |

排序值来自 python 库 `ORDER_FF_FAVORITE_TIME="mr"` / `ORDER_FF_UPDATE_TIME="mp"`；jm-mobile 的枚举标签是「收藏时间 / 更新时间」，完全一致。

### 3.3 协议公共部分

- 请求头：`token = md5hex(ts + "185Hcomic3PAPP7R")`、`tokenparam = "$ts,$appVersion"`（`appVersion` 取 `/setting.jm3_version`，兜底 `2.1.13`）。
- 响应 `{code:200,data:"<base64>"}`：**AES-256-ECB/PKCS7**，key = `ASCII(md5hex(ts + secret))` 全 32 字节。
- cookie 必须带（先 `/setting` 拿 5 个，登录后追加会话 cookie + `AVS`）。

---

## 4. 我们的会话设计

### 4.1 模型与存储

```dart
// lib/data/models/user_session.dart
class UserSession {
  const UserSession({
    required this.uid,
    required this.username,
    required this.avatar,
    required this.favoritesCount,
    required this.favoritesMax,
    required this.level,
    required this.levelName,
    required this.loggedAt,
    required this.state,
  });
  final int uid;
  final String username;
  final String avatar;
  final int favoritesCount;   // album_favorites
  final int favoritesMax;     // album_favorites_max
  final int level;
  final String levelName;
  final int loggedAt;
  final SessionState state;   // local | valid | needsLogin
}

enum SessionState { local, valid, needsLogin }
```

存储：**新建 box `jm_session`**，只放两件事——会话快照 JSON + cookie 列表（`[{domain,path,name,value,expiresAt}]`）。**不放密码**。

```dart
// lib/data/local/session_store.dart
class SessionStore {
  SessionStore(this._box);
  final Box<dynamic> _box;               // HiveBoxes.session

  static const _kSession = 'session';
  static const _kCookies = 'cookies';

  UserSession? readSession() { ... }
  Future<void> writeSession(UserSession s) => _box.put(_kSession, s.toJson());
  List<Cookie> readCookies() { ... }
  Future<void> writeCookies(List<Cookie> c) => _box.put(_kCookies, c.map((e) => e.toJson()).toList());
  Future<void> clear() => _box.deleteAll([_kSession, _kCookies]);
}
```

> Dio 的 cookie 持久化用 `CookieJar` 实现（`PersistCookieJar` 自己落盘，或写一个 `SessionStoreCookieJar` 包一层 Hive）。二选一，别两套并存。

### 4.2 Dio 拦截器链（顺序很重要）

```
dio.interceptors = [
  1. SessionGateInterceptor   // 除 /setting、/login 外，先 await sessionReady（一次即可）
  2. EndpointInterceptor      // 域名轮换：把 /path 换成当前可用 host
  3. TokenInterceptor         // 每请求算 token / tokenparam（含 appVersion）
  4. CookieInterceptor        // 注入/收集 cookie（含 AVS）
  5. DecryptInterceptor       // {code,data} → JSON；code!=200 抛 JmContentException
  6. LoginRequiredInterceptor // 收藏/历史等接口 401/重定向 → sessionStore.markNeedsLogin()
]
```

要点：

- `SessionGateInterceptor` 只对 `/login`、`/setting` 放行（对应 jm-mobile 的 `@GInit`），避免「登录还要等初始化」的死锁。
- **token 每请求现算**，不吃进程常量（改进点 2.7-②）。
- `DecryptInterceptor` 里如果发现响应是 HTML（被重定向到登录页/风控页），直接抛 `SessionExpiredException`。

### 4.3 登录时序

```
用户填用户名/密码
 └─ AuthController.login(user, pass)
     ├─ await api.bootstrap()                       // /setting，拿 cookie/版本（可并发）
     ├─ resp = POST /login (multipart: username, password)
     │     ├─ Set-Cookie 落 CookieJar
     │     └─ 若 body 里带 s → 手动写 cookie AVS=s        // 对齐 python 库
     ├─ 用 resp 组装 UserSession(state: valid) → SessionStore
     ├─ 校验：GET /favorite?page=1&o=mr&folder_id=0
     │     ├─ 200 + JSON → 会话可用
     │     └─ 否则 → state=needsLogin，回滚 cookie，报「登录校验失败」
     ├─ 登录成功即自动同步（0.3.0 落地）：FavoritesSyncNotifier.syncNow()
     │     ├─ 先对账：云端 -> 本地（§7.2）
     │     ├─ 再推送：本地 outbox -> 云端（§7.3）
     │     └─ 结果写会话 favoritesCount + 提示框报「云端 N · 拉回 M · 上传 K」
     └─ 失败提示走对话框（原因归一化：密码错 / 限流 / 人机校验 / 线路异常）
```

> 实现位置：`lib/features/auth/login_page.dart`（对话框与同步编排）、
> `lib/features/collect/favorites_sync.dart`（全局同步状态 `favoritesSyncProvider`）、
> `lib/data/repositories/auth_repository.dart`（`describeLoginFailure` 文案归一）。
> 收藏/评论/点赞三条链路共用一个登录门槛：未登录时点赞与评论弹「登录后才能操作」，
> 收藏仍本地可用（见 `docs/INTERACTION.md` §3）。

### 4.4 自动登录策略（0.3.2 起默认记住密码）

| 策略 | 触发 | 行为 | 默认 |
|---|---|---|---|
| A. cookie 恢复 | 冷启动 | 读 `jm_session.cookies` → `/setting` 刷新 → `GET /favorite?page=1` 校验 | ✅ |
| B. 记住密码（0.3.2 默认开） | A 判定会话失效 | 账号密码存 `flutter_secure_storage`（Android Keystore / Keychain），静默 `POST /login` 一次 → 重写 session + cookie | ✅ 默认开（设置里可关，关掉即清空凭据） |
| C. 什么都不存 | 用户关闭 B 后主动登出 | 冷启动回 `local`，收藏按钮走本地 | 可选 |

> 为什么不照抄 jm-mobile 的「明文存密码」：行为一样（cookie 失效就静默重登），落盘位置换成系统密钥库。
> `flutter_secure_storage` 读写失败时自动降级为「没保存过」，不会把登录流程带崩。
> **主动登出会连凭据一起清**，否则下次冷启动又被自动登回去。

运行时也会自愈：收藏同步遇到鉴权失败（401 / 未登录文案）时，`FavoritesSyncNotifier` 会调
`AccountSessionNotifier.autoRelogin()` 重登一次再重试对账，只试一次、不循环。

会话失效（`needsLogin`）时：不弹全屏登录，只在「我的」页顶栏显示「登录已失效 · 重新登录」，收藏仍可本地用。

### 4.5 失效判定与静默重试

**0.3.1 起收紧（0.3.0 的「每次退出 App 都掉登录」就是这里放太宽）**：

判定信号（任一命中才 `needsLogin`）：

1. HTTP **401**（请求层已统一转成 `JmContentException('登录状态已失效，请重新登录')`）；
2. `code != 200` 且 `errorMsg`/`msg` **明确**含「未登入 / 未登录 / 请先登录 / 登录已失效 / not login / unauthorized」；
3. 会话里 `uid > 0` 但 `jm_session.cookies` 为空（真的没 cookie 可用）。

**不再**作为失效信号：HTML 响应、其它 `code != 200` 的业务错误、线路超时/非 JSON —— 这些只记录并保持登录态，等用户真正操作时再报错。

另外两条配套（同版本）：

- **cookie 每次响应后回写**：`JmApiClient.onCookiesChanged`（节流 2s）→ `SessionStore.writeCookies`；`/setting`、`/login` 后立刻写。否则退出 App 留下的是登录那一刻的旧快照，冷启动必被判失效。
- **冷启动先 `/setting` 再校验**：`恢复 cookie → prepare()（刷新轮换 cookie / 版本）→ GET /favorite?page=1`。

重试：**只重试一次**，且仅当策略 B 开启。重试流程 = 重新 `/login` → 拿新 cookie → 重放原请求；仍失败则 `needsLogin` 并提示，不循环。

### 4.6 登出 / 多账号

```dart
Future<void> logout({bool keepLocalFavorites = true}) async {
  await sessionStore.clear();          // 会话 + cookie 一起清
  await cookieJar.deleteAll();         // 别只清内存
  favoritesStore.onLogout(keepLocal: keepLocalFavorites); // 见 §7.6
  sessionState = SessionState.local;
}
```

- 登出**不删本地收藏**（默认），但把每条 `sync` 从 `synced` 降级为 `localOnly`——它们已不在「当前账号」名下，避免下个账号登录时误推。
- 多账号：`jm_session` 只存当前账号；切号 = 登出 + 登录，历史收藏按 §7.4 的「合并上传」对话框决定去留。

### 4.7 代码骨架

```dart
// lib/data/repositories/auth_repository.dart
class AuthRepository {
  AuthRepository(this._api, this._session);

  Future<UserSession> login(String username, String password) async {
    await _api.bootstrap();                       // /setting：cookie + 版本
    final res = await _api.login(username, password); // POST /login multipart
    if ((res['s'] as String?)?.isNotEmpty ?? false) {
      await _api.setCookie('AVS', res['s'] as String); // 对齐 python 库
    }
    final session = UserSession.fromLoginJson(res, DateTime.now().millisecondsSinceEpoch);
    final ok = await _api.pingFavorite();         // GET /favorite?page=1
    if (!ok) {
      await _session.clear();
      throw const SessionVerifyException('登录校验失败，请重试');
    }
    await _session.writeSession(session);
    await _session.writeCookies(await _api.dumpCookies());
    return session;
  }
}
```

---

## 5. 收藏：数据与存储

### 5.1 模型

```dart
// lib/data/models/favorite_item.dart
enum FavoriteSyncState { localOnly, pendingAdd, pendingRemove, synced, conflict }

class FavoriteItem {
  const FavoriteItem({
    required this.albumId,
    required this.title,
    required this.author,
    required this.categoryId,
    required this.categoryTitle,
    required this.coverUrl,      // 入库时拼好；img_host 变更时按 albumId 重拼
    required this.folderIds,     // 本地文件夹；'default' 恒在
    required this.addedAt,       // 本地收藏时间（ms）
    required this.updateAt,      // 本子最后更新时间（追更角标用）
    this.serverAt,               // 服务端收藏时间（对账后回填）
    this.lastSeenAt = 0,         // 上次进入详情的本地时间（追更用）
    this.sync = FavoriteSyncState.localOnly,
    this.lastError,
  });
}
```

### 5.2 box 规划

| box | key | value | 说明 |
|---|---|---|---|
| `jm_favorites`（已存在） | `albumId` | `FavoriteItem` JSON | 老格式 `{ids:[…]}` 需迁移（§5.3） |
| `jm_favorite_folders`（新） | `folderId` | `{name, colorHex, order, createdAt}` | `default` 恒存在、不可删 |
| `jm_favorite_outbox`（新） | 自增序号 | `{op:'add'\|'remove', albumId, attempts, lastError, createdAt}` | 串行推送，成功即删 |
| `jm_session`（新） | `session` / `cookies` | 会话快照 / cookie 列表 | §4.1 |

### 5.3 迁移（必须做，否则老用户收藏清零）

```dart
Future<void> migrateIfNeeded(Box box) async {
  final legacy = box.get('ids');
  if (legacy is List) {
    for (final id in legacy) {
      final albumId = '$id';
      if (!box.containsKey(albumId)) {
        await box.put(albumId, FavoriteItem(
          albumId: albumId, title: '', author: '', categoryId: '', categoryTitle: '',
          coverUrl: '', folderIds: const ['default'],
          addedAt: DateTime.now().millisecondsSinceEpoch, updateAt: 0,
        ).toJson());
      }
    }
    await box.delete('ids');
  }
}
```

空标题条目：进收藏页时按 `albumId` 惰性补详情（`/album?id=`，并发 3，失败保留占位），不阻塞首屏。

---

## 6. 收藏：交互

### 6.1 收藏按钮（详情页已有，改造）

- **图标是五角星**（0.3.0 起）：未收藏 `star.svg` 描边、已收藏 `star-filled.svg` 实心 + `primary` + 180ms 缩放（1→1.15→1）+ 轻震。点赞用爱心（`heart.svg` / `heart-filled.svg`），两者不要混用。
- 点击：**乐观更新**（本地先写、UI 立即变），再按 `session.state` 决定是否入 outbox。
- 长按：底部弹「加到文件夹」——本地文件夹列表 + 「新建文件夹」。
- SnackBar：「已收藏 · 撤销 / 查看」3 秒；撤销 = 反向写回并**删掉对应 outbox 项**（别把撤销同步出去）。

### 6.2 收藏页（新增 `lib/features/collect/`）

```
┌ 顶部栏：返回 · 我的收藏 · 视图切换 · 多选 ┐
├ 提示条：本地收藏 12 本 · 登录后可同步（未登录/失效时显示） ┤
├ 文件夹 chips：全部 12 | 默认 | 单行本 | 画集 | + 新建 ┤
├ 排序 chips：收藏时间(mr) | 更新时间(mp)               ┤
├ 三列网格：封面 + 1 行标题 + 角标（同步态 / 有更新）      ┤
├ 批量条：移动 / 下载 / 移除 / 取消（长按进入多选）        ┤
└ 触底每页 20、预取 6，下拉刷新，切排序回顶                ┘
```

- 排序切换 → 清空列表 + 回顶 + 重拉（对齐 jm-mobile `animateScrollToItem(0)`）。
- 文件夹 chips 选中 = 本地过滤（`folderIds.contains(id)`），不重新请求。
- 空态：`assets/illustrations/empty-favorite.svg` + 「收藏后会在这里出现，还能追更」+「去首页逛逛」。
- 登录后显示 `已收藏 128 / 500`，≥90% 数字转 `warn` 色，超限禁用收藏按钮。
- 角标：实心橙=已同步 / 空心橙=待同步 / 灰=仅本地；有更新再叠「更新」小标。

### 6.3 入口

- 我的 → 统计卡「收藏 N」（可点）。
- 我的 → 「收藏与历史」分组：我的收藏（条数 + 箭头）、观看历史、同步状态（未登录 / 上次同步 12:31 / 待同步 3 条）。
- 详情页收藏成功 SnackBar「查看」直达。
- Dock 保持三档（首页/我的/下载），收藏是二级页 `/collect`。

### 6.4 追更

`有更新 = updateAt > lastSeenAt`；进入详情页即 `lastSeenAt = now`，角标消失。拿不到更新时间的退化为 `updateAt > addedAt + 7d` 弱提示。

---

## 7. 收藏：同步引擎（登录后）

### 7.1 状态机

```
            ┌───────── 未登录 / needsLogin ─────────┐
            ▼                                       │
        localOnly ──登录+校验通过──▶ pendingAdd ──POST(type=add)──▶ synced
                                   ▲    │                            │
                                   │    └─失败(网络/风控)─退避重试────┘
                                   │                                 │
        synced ──本地取消──▶ pendingRemove ──POST(type=remove)──▶ (删本地记录)
                                   ▲                                 │
                                   └──── 对账发现服务端已无 ──▶ conflict
```

### 7.2 对账（触发：登录校验通过 / 手动「立即同步」/ 已登录冷启动且距上次 > 15min）

```
1. 拉全量：/favorite?page=1..N&o=mr&folder_id=0，翻到 list 为空为止，
   页间隔 ≥300ms（风控保护），上限 100 页。
2. 构建 serverIds / localIds。
3. 逐条决策：
   - 只在服务端：本地新增（sync=synced，标题/封面惰性补）
   - 只在本地且 sync ∈ {localOnly, pendingAdd}：入 outbox(add)
   - 只在本地且 sync == pendingRemove：直接删本地（本地撤销过，服务端也没有）
   - 两边都有：sync=synced，保留本地文件夹/标题快照
4. 写 meta.syncAt / serverCount，用 count 校准计数。
```

首次登录且本地已有收藏时先弹三选：**合并上传**（默认）/ **只保留服务端**（二次确认）/ **先看差异**（进收藏页逐条处理）。

### 7.3 push outbox（串行、可中断）

```dart
Future<bool> _pushOnce(OutboxEntry e) async {
  final resp = await api.toggleFavorite(e.albumId);       // POST /favorite {aid}
  final actual = resp.type;                                // 'add' | 'remove'
  final expected = e.op == FavoriteOp.add ? 'add' : 'remove';
  if (actual == expected) return true;

  // 与预期相反 → 说明服务端状态被我们切反了，立刻反向补发扳回来
  await api.toggleFavorite(e.albumId);
  markConflict(e.albumId);
  return false;
}
```

- 每条之间 `await Future.delayed(400ms)`；单条退避 `2s → 8s → 30s`（最多 5 次），失败保留 outbox。
- 连续 3 条业务失败（未登录/风控）→ 停本轮，提示「同步暂停，稍后重试」。
- 网络异常只影响同步，**不影响本地读写**。

### 7.4 上限与计数

- `maxCount` 来自登录响应 `album_favorites_max`；`count` 用 `GET /favorite?page=1` 的 `count` 校准。
- 本地条数 > max 时：允许取消收藏、禁止新增，并显示「已满 500/500」。

### 7.5 会话失效对收藏的影响

| 会话状态 | 收藏行为 | UI |
|---|---|---|
| `local` | 只写本地，`sync=localOnly` | 顶部「本地收藏 · 登录后可同步」 |
| `valid` | 写本地 + outbox | 角标显示同步态 |
| `needsLogin` | 只写本地，outbox 保留不推 | 顶部「登录已失效 · 重新登录」+ 角标转灰 |

### 7.6 登出时

`synced → localOnly`（不删记录），outbox 清空（避免把上个账号的操作推到下个账号）。

---

## 8. 与其它模块联动

| 模块 | 联动 |
|---|---|
| 下载（PLAN §8） | 收藏页批量入下载队列；完成回写角标（可选） |
| 阅读（PLAN §7.6） | 卡片进详情；「继续阅读」读 `progress:{albumId}:{chapterId}` |
| 搜索（PLAN §7.4） | 结果卡复用同一收藏按钮组件 |
| 我的（PLAN §7.7） | 统计卡 + 收藏入口 + 同步状态 + 登录/登出 |
| 首页 | 不加收藏入口，避免导航噪音 |

---

## 9. 落地拆分（F0–F5）

| 阶段 | 内容 | 接触文件 | 验收 |
|---|---|---|---|
| **F0 会话** | `UserSession` / `SessionStore` / `AuthRepository` / 拦截器链 / 登录页 | `data/models/user_session.dart`、`data/local/session_store.dart`、`data/repositories/auth_repository.dart`、`core/network/dio_factory.dart`、`features/auth/login_page.dart` | 能登录、杀进程后仍登录、登出三处皆清 |
| **F1 收藏数据** | `FavoriteItem` + Store 改造（per-album + 迁移 + 文件夹 + outbox） | `data/models/favorite_item.dart`、`data/local/progress_store.dart`、`local/hive_init.dart` | 老数据迁移不丢；store 用例全绿 |
| **F2 收藏页** | 收藏页 + 文件夹 + 排序 + 视图 + 空态 + 我的入口 | `features/collect/*`、`core/router/app_router.dart`、`features/mine/mine_page.dart` | 离线可开、可删、可切文件夹、可排序 |
| **F3 详情联动** | 乐观更新 + undo + 长按加夹 + SnackBar | `features/album/album_page.dart`、`features/home/widgets/album_card.dart` | 0 帧延迟；3 秒可撤销 |
| **F4 同步** | 对账 + outbox + 退避 + 上限 | `data/repositories/favorite_sync_service.dart`、`data/sources/jm_api_client.dart` | 登录后双向一致；断网排队不丢 |
| **F5 批量与追更** | 多选批量 + 追更角标 + 失效标记 | `features/collect/widgets/*` | 批量移除 10 条一次成功；换设备角标正确 |

顺序：**F0 → F1 → F2 → F3**（到这里已经很好用）→ F4 → F5。

---

## 10. 测试矩阵

| 用例 | 断言 |
|---|---|
| 登录成功 | 写 session + cookie；`pingFavorite` 通过；`favoritesMax` 落库 |
| 登录失败 | 不写 session；错误文案透出；cookie 回滚 |
| `AVS` 注入 | 响应带 `s` 时 cookie 里有 `AVS` |
| 冷启动恢复 | 有 cookie → `valid`，不重登；无 cookie → `local` |
| 失效判定 | 403 / HTML 响应 / `code!=200` 三种都转 `needsLogin` |
| 登出 | session、cookie、outbox 全清；本地收藏保留且降级 `localOnly` |
| 迁移 | 旧 `ids:[1,2]` → 两条记录，重复执行无副作用 |
| toggle 本地 | 收藏→取消→收藏计数正确；重复收藏幂等 |
| outbox 幂等 | 同 albumId 连续 add/remove/add，最终只留 1 条 add |
| 对账四象限 | 服务端有/本地有/都有/都没有 → 结果正确，不产生重复 outbox |
| toggle 反向 | mock 返回反向 `type` → 第二次请求 + 标 conflict |
| 退避 | 连续 3 次失败 → outbox 保留、attempts=3、可续推 |
| 上限 | max=500、本地 500 条 → 按钮禁用并提示 |
| 离线 | 飞行模式收藏/取消/切夹/删除正常；恢复后一次同步通过 |
| 失效条目 | 详情 404 → 卡片「已失效」，记录保留 |

---

## 11. 不做 / 风险

- **不做**：服务端收藏夹建/改/删、收藏夹封面、跨账号迁移、收藏导出（可后加 JSON 导出）、`/like`、签到 `daily`、评论。
- **风险 1**：`POST /favorite` toggle + 风控 → 串行 + 400ms 间隔 + 反向校正。
- **风险 2**：`GET /favorite` 的 `image` 可能空 → 封面自拼；计数只用 `count`。
- **风险 3**：登录失效没有明确错误码 → 用「HTML 响应 / 403 / code!=200」三信号判定。
- **风险 4**：`/login` 是 multipart，Dio 需 `FormData`；别写成 JSON body。
- **兼容**：jm-mobile 的每页 20 是客户端行为，服务端可能给更多；按「翻到空页为止」实现。

---

## 附：与 `Plan/PLAN.md` 的对应

| 本文 | PLAN 对应 |
|---|---|
| §3 接口 | §5.4 端点表（`/favorite`、`/login`、`/watch_list`） |
| §4 会话 | §7.9（会话/同步约束）+ §11（失败兜底：会话失效） |
| §6 UI | §7.9（收藏页）+ `docs/ui-draft.html` 第 7 屏（编号 26–30） |
| §9 拆分 | §9 M4.5（收藏与登录） |
