# Fix Plan — JM 网络模块连通性修复

- 日期：2026-11-15
- 范围：`jm_comic` 网络层（线路发现、连通性检测、请求轮换、图床兜底、设置页网络区）
- 结论一句话：**连通性检测不是主因，协议层把 AES-256 的 key 截断成 16 字节（当成 AES-128）才是主因** —— 真实响应解不开，每条线路都表现为「HTTP 200 但解密失败」，于是全线路被判死。发现源单一、只读 `Server`、无国内地址、串行重试则把这个故障放大成「首屏几十秒 + 全红」。
- 详细设计/排障见 [docs/NETWORK_MODULE.md](docs/NETWORK_MODULE.md)；最近一次实测留档见 [docs/NETWORK_DOMAINS_2026-11-15.md](docs/NETWORK_DOMAINS_2026-11-15.md)。

---

## 1. 发现的问题（按严重度）

### P0 — AES key 长度错误（真正的「连不上」）

- 旧实现：`JmCrypto.keyBytes()` 取 `ASCII(md5hex(ts + secret)).sublist(0, 16)`，按 **AES-128-ECB** 解密。
- 真实协议：key 是 `md5hex(...)` 的**全部 32 个 ASCII 字节**，即 **AES-256-ECB/PKCS7**。
- 现场证据（同一 `ts=1794712726`、同一份 `/setting` 响应）：

  | key 长度 | 结果 |
  |---|---|
  | 16 字节（AES-128） | `Padding is invalid and cannot be removed.` |
  | 32 字节（AES-256） | `{"version":"1.8.2","test_version":"1.8.2",...}` |

- 为什么测试没发现：fixture 由同一套错误实现加密，自洽；`tools/probe_api.ps1` 用的是 PowerShell 全量 32 字节，所以脚本一直全绿，App 一直全红。
- 修复：`lib/data/sources/jm_crypto.dart` 的 `keyBytes` 返回 32 字节；补 .NET 侧交叉密文 + 真实响应 fixture 锁死回归。

### P1 — 域名发现只有 3 个海外 TOS 源

- 三个 `newsvr-2025.txt` 全在境外 CDN（bytepluses）；国内网络下可能全部超时。
- 修复：新增四类源，单源 6s 超时、互不阻塞：
  1. 内置种子 `assets/data/jm_hosts.json`（唯一不依赖网络的源）；
  2. 三个 TOS 域名服务；
  3. 发布页 `jmcomictt.site` / `jmcomicgo.org`（国内域名唯一来源）；
  4. GitHub 镜像 `JMComic-Crawler-Python` 的 `DOMAIN_API_LIST` / `DOMAIN_IMAGE_LIST`。

### P1 — 域名服务只读 `Server`

- 明文实际长这样（实测，AES-256 + 空 ts）：

  ```json
  {"Setting":["www.cdnbtd.cc","www.cdnutc.cc","www.cdngwc.net","www.cdngwc.club"],
   "Server":["www.cdnbtd.cc","www.cdnutc.cc","www.cdngwc.net","www.cdngwc.club"],
   "jm3_Server":[["www.cdnbtd.cc","線路1"],["www.cdnutc.cc","線路2"],["www.cdngwc.net","線路3"],
                 ["www.cdngwc.club","線路4"],["www.cdnutc.me","線路5"]]}
  ```

- 旧实现只读 `Server`：丢掉 `www.cdnutc.me`（第 5 条）和全部「線路N」标签。
- 修复：`JmHostCatalog.parseDomainServer()` 三张表全收，标签保留。

### P1 — 「发现成功」只看 HTTP 200，没有真探测

- 旧 `_fetchHosts`：请求成功即返回，不校验接口是否真的能用。
- 修复：新增 `JmHostProbe`，判定标准：
  - API：`GET /setting` + `token`/`tokenparam` → `code=200` → AES-256 解得开 → `jm3_version`/`img_host` 至少一个非空；
  - 图床：`GET /media/albums/1490702_3x4.jpg` → 200 且 `content-type: image/*` 且 body 非空；
  - 网页：`GET /` → 200 HTML 且不是 Cloudflare 挑战页。

### P1 — 串行轮换 + 全局超时（15s 连接 / 35s 收发）

- 旧 `_requestApi` 对每台 host 顺序 await，7 台里前 3 台黑洞就 >45s；首屏像卡死。
- 修复：
  - 单次尝试 `requestAttemptTimeout = 9s`；
  - 单请求总预算 `requestTotalBudget = 24s`、图片 `imageTotalBudget = 40s`，到点即停；
  - 探测专用 Dio：连接 5s / 收发 8s。

### P2 — 完全没有国内地址

- 发布页的国内域名从未进入代码；海外 CDN 被墙时无任何退路。
- 修复：`JmConstants.domesticHosts` + 种子文件 + 图床兜底链路（详见 §2）。

### P2 — 探测结论不落盘

- 旧实现只维护一个「成功置顶」的 host 顺序，没有延迟/失败/时间戳。
- 修复：`EndpointStore` 新增 `jm_host_health`（SharedPreferences JSON）：`host/kind/ok/latencyMs/checkedAt/status/failCount`，上限 80 条；排序 + 10 分钟冷却 + 30 分钟 TTL。

### P2 — 「自动切换线路」是假开关

- `SettingsStore.autoSwitchHost` 只写不读。
- 修复：`JmApiClient(autoSwitchHost: () => ref.read(settingsProvider).autoSwitchHost)`；关闭后只试首条线路。

---

## 2. 实测数据（2026-11-15，出口为本机 FlClash 代理）

> 延迟里的 ~6s 是代理链路固定开销，不代表站点真实延迟。

### API 线路（APP 协议，`/setting` 全链路）

| 主机 | 标签 | 状态 | 延迟 | 来源 |
|---|---|---|---|---|
| `www.cdnutc.cc` | 線路2 | ok | 6.2s | TOS `Setting`/`Server`/`jm3_Server` |
| `www.cdngwc.net` | 線路3 | ok | 6.2s | TOS + GitHub 镜像 |
| `www.cdnhjk.net` | — | ok | 7.3s | GitHub 镜像（波动大） |
| `www.cdnbtd.cc` | 線路1 | ok | 7.4s | TOS |
| `www.cdngwc.club` | 線路4 | ok | 7.4s | TOS + GitHub 镜像 |
| `www.cdngwc.cc` | — | ok | 8.7s | GitHub 镜像 |
| `www.cdnutc.me` | 線路5 | timeout | 15s+ | TOS `jm3_Server`（不稳定） |

### 国内地址（发布页「內地 / 分流」，本次核心新增）

| 域名 | 分区 | `/setting` | `/media/albums/1490702_3x4.jpg` | 定位 |
|---|---|---|---|---|
| `comic18j-susu.com` | 內地 | 404 | 200 `image/jpeg` 86KB | 只能当图床 |
| `comic18j-nico.work` | 分流1 | 404 | 200 `image/jpeg` 86KB | 只能当图床 |
| `comic18j-neo.com` | 分流2 | 404 | 200 `image/jpeg` 86KB | 只能当图床 |

- 网页 `https://comic18j-*.com/` → 301 到 `https://18comic.vip/` → Cloudflare「Just a moment...」403。
- 结论：**国内域名不提供 APP 接口**，不要塞进 API 线路表；但 `/media/...` 直出图片，是海外图床全挂时的国内兜底。
- 发布页镜像：`jmcomicgo.org` 302 到 `jmcomictt.site`，两边解析结果一致（7 个域名）。

### 网页域名（HTML 兜底）

| 域名 | 状态 |
|---|---|
| `18comic.ink` | ok（200 HTML） |
| `18comic.vip` / `jmcomic-zzz.one` / `jmcomic-zzz.org` | Cloudflare 挑战（403） |

### 种子现状（`assets/data/jm_hosts.json`）

- `generatedAt`：2026-11-15T11:39:10+08:00
- 规模：API 7 条（6 ok）/ 图床 25 条（含 3 个国内）/ 网页 7 条
- 图床来源：`/setting.img_host` 反向收编 3 条（当天轮换的 `cdn-msp*` / `cdn-msp12` 前缀）、GitHub `DOMAIN_IMAGE_LIST` 6 条、`/media` 可用的 API/网页域名、国内 3 条。

---

## 3. 改动清单

### 新增

| 文件 | 作用 |
|---|---|
| `lib/core/utils/host_normalizer.dart` | 域名归一化（去协议/路径/端口/大小写）+ 国内域名判定，线路表/健康表共用 |
| `lib/data/models/jm_host_entry.dart` | 线路模型：`kind(api/image/web)`、`label`、`status`、`latencyMs`、`domestic`、`sources`、`checkedAt`、`settingImgHost` |
| `lib/data/sources/jm_host_catalog.dart` | 四源解析：种子 JSON / 域名服务明文（三张表）/ 发布页 HTML（五分区）/ GitHub 配置；含 ok 优先的合并规则 |
| `lib/data/sources/jm_host_probe.dart` | 真探测：`/setting` 全链路、`/media` 封面、首页 HTML；批量并发 + 状态分类（timeout/tls_error/http_/not_json/decrypt_failed/cloudflare_challenge…） |
| `assets/data/jm_hosts.json` | 打进 APK 的线路种子（含最近实测状态与时间戳） |
| `tools/probe_hosts.ps1` | 线路发现 + 实测 + 生成种子与报告（`-Proxy` / `-Concurrency` / `-TimeoutSec` / `-SkipProbe`），增量复测 |
| `docs/NETWORK_MODULE.md` | 模块设计、判定标准、排序/冷却、排障手册 |
| `docs/NETWORK_DOMAINS_2026-11-15.md` | 本次全量实测留档（脚本生成） |
| `test/data/jm_host_catalog_test.dart` | 四源解析 + 合并 + 打包种子自检 |
| `test/data/jm_host_probe_test.dart` | ok / 403 / 解密失败 / 非 JSON / code!=200 / 图床返回 HTML / Cloudflare |
| `test/data/jm_endpoint_resolver_test.dart` | 多源合并、种子回填跳过探测、缓存复用、全量测速 |
| `test/data/endpoint_store_test.dart` | 排序、冷却、手填置顶、图床去重、清理 |
| `test/data/jm_api_client_rotation_test.dart` | 首台返回 HTML 自动换线、成功线路置顶、全挂报错 |
| `test/manual/network_live_test.dart` | 实网联调（默认 skip，`--dart-define=JM_LIVE=true` 开启） |
| `test/fixtures/setting_envelope_live.json` | 真实 `/setting` 响应采样（AES-256 端到端向量） |

### 修改

| 文件 | 关键改动 |
|---|---|
| `lib/data/sources/jm_crypto.dart` | `keyBytes` 16 → **32 字节**（AES-256）；文档写明「不能截断」及症状 |
| `lib/core/constants/jm_constants.dart` | 线路表按实测重排；新增 `domesticHosts` / `overseasWebHosts` / `webHosts` / `publicationUrls` / `domainMirrorUrls` / `hostSeedAsset` / 探测与超时常量 |
| `lib/core/network/dio_factory.dart` | `createJmDio` 可配 `connectTimeout`（默认 15→8s）/ `ioTimeout` / `idleTimeout`，供探测专用实例用 5s |
| `lib/data/local/endpoint_store.dart` | 新增健康表 `JmHostHealth`（持久化 JSON）、`recordHealth(checkedAt)`、`hasFreshHealth`、`isCoolingDown`、`resetHealth`、`webHosts`；`apiHosts/imageHosts` 改为健康度排序；手填线路 rank -1 永久置顶；discovered 列表上限 30 |
| `lib/data/sources/jm_endpoint_resolver.dart` | 重写：并发多源发现 → 合并 → 种子健康回填 → 有新鲜 ok 则跳过探测 → 否则首批 4 台并发实测 → 落盘 → `JmDiscoveryReport`；新增 `probeAll()` / `lastReport` |
| `lib/data/sources/jm_api_client.dart` | 按健康度轮换 + 冷却跳过 + 会话粘性（`_preferActive`）+ 单次 9s + 总预算 24s/40s + 失败写健康表 + `autoSwitchHost` 接线 + 更细的失败状态 |
| `lib/data/repositories/session_repository.dart` | `rediscover()` 清健康表并强制重跑；新增 `probeAll()`、`apiHealth`、`statusLabel()`、`webHosts` |
| `lib/core/di/providers.dart` | 新增 `jmProbeDioProvider`（5s/8s）、`hostProbeProvider`；resolver 注入 probe；HTML 兜底改为「API 域名 → 网页域名（含国内）」 |
| `lib/features/mine/settings_page.dart` | 新增「线路测速」+ 结果列表（可用/超时/TLS/人机校验/延迟/国内标签）；「重新探测线路」走 `rediscover()`；排障文案指向 `tools/probe_hosts.ps1` |
| `pubspec.yaml` | 注册 `assets/data/` |
| `tools/probe_api.ps1` | 默认线路表改为读种子（实测 ok 优先）；AES 说明更正为 AES-256 |
| `README.md` / `PLAN.md` / `docs/IMPLEMENTATION.md` | 更正 AES 结论（16 → 32 字节）、补充线路/国内域名/新工具与新文档 |

### 行为对比

| 场景 | 修复前 | 修复后 |
|---|---|---|
| 单台线路响应 | HTTP 200 但解密失败 → 判死 | AES-256 解开 → 正常出数据 |
| 冷启动线路来源 | 3 个海外 TOS，全挂就只剩过期硬编码 | 种子 + TOS + 发布页 + GitHub 镜像 + 内置兜底 |
| 冷启动耗时 | 最坏 7 台 × (15s+35s) 分钟级 | 有新鲜 ok 线路 0 探测；否则首批 4 台 × 5s，有 ok 即停；单请求 24s 封顶 |
| 国内网络 | 无任何国内地址 | 3 个 `comic18j-*` 作图床兜底；国内网页域名参与 HTML 兜底 |
| 失败线路 | 每次都先撞一遍 | 10 分钟冷却，排到队尾 |
| 图床 | 固定 6 条海外 | `/setting.img_host` 动态 + 种子实测 + 国内兜底（25 条） |
| 设置页 | 只显示「当前线路」 | 可一键全量测速，逐条展示状态/延迟/国内标签 |
| 自动切换开关 | 无效果 | 关闭后只试首条线路 |

---

## 4. 测试与验证

```powershell
$env:Path = 'D:\data\tools\flutter\bin;' + $env:Path
cd D:\data\product\JMComic
flutter analyze     # No issues found!
flutter test        # 111 passed / 2 skipped（skip = 实网用例）
pwsh -File .\tools\probe_hosts.ps1 -Proxy http://127.0.0.1:7890 -Concurrency 8
pwsh -File .\tools\probe_api.ps1 -Proxy http://127.0.0.1:7890
flutter test --dart-define=JM_LIVE=true --dart-define=JM_PROXY=http://127.0.0.1:7890 test/manual/network_live_test.dart
```

结果：

- `flutter analyze`：无问题。
- `flutter test`：111 通过 / 2 跳过；新增 6 组网络用例全绿（crypto 含真实响应向量、catalog、probe、store、resolver、rotation）。
- `tools/probe_hosts.ps1`：26 台主机实测，API 6 可用 / 图床 25 可用，种子与报告已刷新。
- `tools/probe_api.ps1`：`/setting`、`/promote`（8 模块）、`/latest`（80 条）、`/categories`（10 分类）全绿。
- 实网 Dart 侧：`www.cdnutc.cc` / `www.cdngwc.net` / `www.cdngwc.cc` ok，国内三个域名 `/media` 全部 200 86KB。

---

## 5. 剩余事项

| # | 事项 | 说明 |
|---|---|---|
| 1 | 重打 APK | ✅ **已完成（2026-11-15，见 §7）**：SDK 组件已恢复（cmdline-tools 23 / platform-tools 37 / android-36 / build-tools 36 / NDK r28c），`flutter build apk --release` 通过，产物 61.97 MB，SHA256 `D0A321B3…D9DAFB6B` |
| 2 | 定期刷新种子 | 线路会漂移：至少每次发版前跑一次 `tools/probe_hosts.ps1`；`/setting.img_host` 当天就会换成 `cdn-msp*` / `cdn-msp12` / `tencent` 等前缀，种子里的 `settingImgHost` 是当时快照 |
| 3 | CI 守护 | 建议把 `require_trailing_commas` 之外的格式检查固定下来；另外加一条断言「`JmCrypto.keyBytes(ts).length == 32`」防止再次退回 AES-128 |
| 4 | 国内 API 线路 | 目前发布页没有提供国内 APP 接口域名；若后续出现，只需在 `JmConstants`/种子 `api` 组新增，无需改逻辑 |
| 5 | HTML 兜底 | 国内网页域名仍会被 Cloudflare 挑战拦截（403），HTML 兜底实际可用的是 `18comic.ink`；如需强化，可加 WebView 取 Cookie 的方案（本次未做） |
| 6 | 实网用例纳入夜间任务 | `test/manual/network_live_test.dart` 需要出口网络，适合独立定时跑，不进主 CI |

---

## 6. 附：种子 schema（`assets/data/jm_hosts.json`）

```json
{
  "schema": 2,
  "generatedAt": "2026-11-15T11:39:10+08:00",
  "network": "proxy:http://127.0.0.1:7890",
  "sampleAlbum": "1490702",
  "api":   [{ "host": "...", "label": "線路2", "status": "ok", "latencyMs": 6202,
              "httpStatus": 200, "domestic": false, "sources": ["tos:jm3_Server"],
              "firstSeen": "2026-11-15", "checkedAt": "...",
              "settingImgHost": "https://cdn-msp3.jmdanjonproxy.vip", "appVersion": "2.1.13" }],
  "image": [{ "host": "...", "status": "ok", "latencyMs": 5981, "domestic": true, "sources": ["media-from:web"] }],
  "web":   [{ "host": "comic18j-susu.com", "label": "內地", "status": "cloudflare_challenge",
              "httpStatus": 403, "domestic": true }]
}
```

- `status` 取值：`ok` / `timeout` / `tls_error` / `http_4xx` / `http_5xx` / `not_json` / `code_xxx` / `decrypt_failed` / `payload_unexpected` / `cloudflare_challenge` / `unknown`。
- App 侧：种子只提供「候选 + 历史结论」，真正的可用性由 `/setting` 实测（`checkedAt` 超过 30 分钟 TTL 会重测）。

---

## 7. 执行记录（2026-11-15 接手复核）

本节由本次接手会话补记；上面的代码改动在树上已全部存在，这里只记录复核与收尾结果。

1. **代码核对**：`JmCrypto.keyBytes` 返回 32 字节（AES-256），`test/data/jm_crypto_test.dart` 断言 `key.length == 32` 且含真实 `/setting` 采样向量；`jm_host_catalog` 三张表（`Setting`/`Server`/`jm3_Server`）与发布页、GitHub 镜像、种子四源解析均在；`jm_host_probe` 状态覆盖 `decrypt_failed` / `not_json` / `code_xxx` / `cloudflare_challenge` / `tls_error`；`jm_api_client` 有 9s 单次 + 24s/40s 预算、冷却与 `autoSwitchHost`；设置页「线路测速」已接 `probeAll()`。
2. **静态检查与测试**：`flutter analyze` → No issues found；`flutter test` → **111 passed / 2 skipped**（skip 为实网用例），与 §4 记录一致。
3. **实网复跑**（`--dart-define=JM_LIVE=true --dart-define=JM_PROXY=http://127.0.0.1:7890`）：
   - API：`www.cdnutc.cc` 5977ms、`www.cdngwc.net` 6013ms、`www.cdngwc.cc` 6556ms、`www.cdngwc.club` 8993ms —— 全部 `ok`，
     `img_host` 已漂移为 `tencent.jmdanjonproxy.xyz` / `cdn-msp2.jmapiproxy3.cc` / `cdn-msp.jmdanjonproxy.xyz`（印证 §5-2 的漂移结论）；
   - 国内图床：`comic18j-susu.com` / `comic18j-nico.work` / `comic18j-neo.com` 均 200、86KB。
4. **构建环境（§5-1 的阻塞项）已修**：本机 SDK 组件全丢，已按 `docs/IMPLEMENTATION.md` §七恢复
   cmdline-tools 23.0.0 + platform-tools 37.0.1 + `platforms;android-36` + `build-tools;36.0.0` +
   `ndk;28.2.13676358`（r28c，手工放置，因新版 Android CLI 不认 `ndk;ver` 语法；`jni` 插件需要真 NDK）。
5. **重打 APK 成功**：61.97 MB，SHA256 `D0A321B3…D9DAFB6B`，已归档 `dist\JMComic-0.1.0-release.apk`
   （minSdk 29 / targetSdk 35 / compileSdk 36，3 ABI，17 个位图 + `assets/data/jm_hosts.json` 均在包内）。
6. **`.gitignore` 已补**非必须文件（设计草稿 PSD、`dist/`、构建产物、IDE、Python 缓存等），见仓库根 `.gitignore`。
