# JMComic 0.3.1 发布说明

> 版本：`0.3.1+5` · 平台：Android 8.0+（minSdk 29） · 产物：`dist/JMComic-0.3.1-release.apk`（66,543,897 B / 63.5 MB，SHA-256 `9553c27f0567b5d2c706af50ab4b69cae41dadc32d3f5c51a87ecb5ef946b970`）
> 上一版：`0.3.0+4`

## 修复

- **登录态不再随退出 App 丢失**（0.3.0 的严重回归）
  - 根因有两个：
    1. cookie 只在「登录成功」那一刻写盘一次。站点每次响应（尤其 `/setting`）都会轮换会话 cookie，退出 App 后 Hive 里留下的是旧快照，冷启动拿去打 `/favorite` 就被判未登录。
    2. 冷启动校验没先跑 `/setting`，且把**任何**业务错误都当成「会话失效」直接降级，等于一次抖动就踢下线。
  - 修法：
    - `JmApiClient` 新增 `onCookiesChanged`，每次响应后（节流 2s）把 cookie 快照回写 `jm_session`；`/setting`、`/login` 后强制立刻写一次；
    - 冷启动顺序改为 **恢复 cookie → 跑一次 `/setting` → 用 `/favorite?page=1` 校验**；
    - 只有服务端**明确**说「未登录 / 请先登录 / 会话失效 / 401」才降级成 `needsLogin`，其它业务错误与网络错误一律保持登录态。
- **评论区出现 `<div></div>` 等标签**
  - 站点评论正文/昵称是富文本，`<div>`、`<br>`、`&nbsp;`、`&lt;` 直接落进 `Text` 就露馅。
  - 现在解析时统一走 `JmComment.cleanText()`：块级标签补换行、`<br>` 转换行、实体解码（`html` 包 `parseFragment`）、压缩多余空行；标签全删、纯文本保留。
- **点赞不再转圈**：点下去立刻变「已点赞 N」，`POST /like` 在后台跑；失败自动回滚并提示「点赞失败：…」。
- **发评论不再等网络**：面板点「发送」立即关闭、评论立刻以「发送中」标记插到列表顶部，后台提交；成功只摘掉标记（不会因服务端暂未收录而凭空消失），失败撤回该条并提示。

## 其它

- `sessionStoreProvider` 从 `features/collect` 迁到 `core/di`（网络层要持续回写 cookie），原导入路径通过 `export` 保持兼容。
- 详情页动作条去掉 loading 态，只保留「未赞 / 已赞」两态。
- 修掉 `about_page` 一处 trailing comma 与若干 lint。

## 升级提示

- 无需迁移：`jm_session` 结构未变，旧用户升级后**第一次仍需重新登录一次**（0.3.0 存下的 cookie 已被站点轮换，无法救回），之后即可长期保持。
- 收藏账本、阅读进度、下载历史不变。

## 校验

```powershell
flutter analyze                        # 0 issue
flutter test                           # 145 passed / 2 skipped（实网用例需 JM_LIVE=true）
pwsh -File tools/check_ui_rules.ps1    # 通过
flutter build apk --release            # 产物见 dist/JMComic-0.3.1-release.apk
```

新增回归用例：

- `favorites_test.dart`：非鉴权业务错误**不**把用户踢下线；
- `interaction_test.dart`：评论正文剥离 `<div>` / `<br>` / `&nbsp;` / `&lt;`。
