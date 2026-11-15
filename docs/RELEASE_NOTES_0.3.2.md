# JMComic 0.3.2 发布说明

> 版本：`0.3.2+6` · 平台：Android 8.0+（minSdk 29） · 产物：`dist/JMComic-0.3.2-release.apk`（68,215,605 B / 65.1 MB，SHA-256 `40c298013d7d85c7c2f88c697fb1e2f6b3ac8ca082c6a3d1e3a948cfe68af159`）
> 上一版：`0.3.1+5`

## 登录态（这次是彻底修好）

0.3.1 只做了「cookie 持久化 + 冷启动先跑 /setting」，但如果站点把你的会话 cookie 判死（换 IP、换设备、隔太久），cookie 再新也没用——所以仍然会掉登录。

0.3.2 补上真正管用的那层：**记住密码 + 自动重登**。

| 层次 | 触发 | 行为 |
|---|---|---|
| 1. cookie | 每次响应 | 节流 2s 回写 `jm_session`，`/setting`、`/login` 后立刻写 |
| 2. 校验 | 冷启动 | 恢复 cookie → 跑 `/setting`（刷新轮换值）→ `GET /favorite?page=1` |
| 3. **自动重登** | cookie 校验判定失效 | 从系统密钥库读账号密码 → 静默 `POST /login` → 重写 session + cookie，继续用 |
| 4. 兜底 | 重登也失败 | 才标 `needsLogin`，本地收藏照常可用 |

- 密码存 **Android Keystore / iOS Keychain**（`flutter_secure_storage`，不落明文）；读写异常自动降级为「未保存」，不会把登录流程带崩。
- 设置里新增 **「记住密码（自动登录）」开关，默认开**；关掉或「清除已保存的密码」会立刻删凭据。**主动登出也会清凭据**（避免下次冷启动又被登回去）。
- 运行时自愈：收藏同步遇到鉴权失败（401 / 未登录文案）时，会自动重登一次并重试对账，只试一次不循环。
- App 启动即恢复会话（不再等用户点进「我的」），首屏阶段就把登录态准备好。

## 其它

- 登录页新增「记住密码」开关与说明文案，原来的「不保存密码」表述已按新策略改写。
- 新增 `CredentialVault` 抽象（`SecureCredentialVault` / 测试用 `MemoryCredentialVault`），`AuthRepository` 可注入，便于单测。
- 依赖新增 `flutter_secure_storage: 9.2.2`；同时补了 `android/app/proguard-rules.pro`（Tink 的 errorprone / google-http-client / joda-time 都是 compileOnly，不 `dontwarn` 会导致 R8 minify 直接失败）。

## 升级提示

- 0.3.1 用户升级后**仍需要手动登录一次**（0.3.1 没存过密码）；这一次登录会写入密钥库，之后退出 App 不再掉登录。
- 收藏账本、阅读进度、下载历史不变。

## 校验

```powershell
flutter analyze                        # 0 issue
flutter test                           # 148 passed / 2 skipped（实网用例需 JM_LIVE=true）
flutter build apk --release            # 产物见 dist/JMComic-0.3.2-release.apk
```

新增用例：cookie 失效 → 用保存的密码自动重登；关闭「记住密码」不自动登录；登出清空凭据。
