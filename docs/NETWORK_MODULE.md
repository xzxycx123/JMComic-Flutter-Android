# JM 网络模块：线路发现与连通性检测

> 2026-11-15 重写。涉及文件：`lib/data/sources/jm_host_catalog.dart`、`jm_host_probe.dart`、
> `jm_endpoint_resolver.dart`、`jm_api_client.dart`、`lib/data/local/endpoint_store.dart`、
> `lib/data/models/jm_host_entry.dart`、`assets/data/jm_hosts.json`、`tools/probe_hosts.ps1`。
> 最近一次全量实测留档：`docs/NETWORK_DOMAINS_2026-11-15.md`。

## 1. 这次到底坏在哪

现象：冷启动很久、首页报「所有 API 线路均连接失败」、设置页「重新探测线路」也没用。

逐项定位（都可复现）：

| # | 问题 | 证据 | 后果 |
|---|---|---|---|
| 1 | **AES key 被截断成 16 字节**，按 AES-128 解密 | 同一 `ts` 下 16 字节 key 抛 `Padding is invalid and cannot be removed.`；32 字节 key 解出 `{"version":"1.8.2",…}` | HTTP 200 但每条线路都「解密失败」→ 全线路不可用 |
| 2 | 域名服务只读 `Server` | 明文里还有 `jm3_Server`（5 条带标签，含 `www.cdnutc.me`）和 `Setting` | 线路表少一条 + 丢失「線路N」标签 |
| 3 | 发现结果不验证 | `_fetchHosts` 只要 HTTP 200 就返回 | 能连上但接口挂掉的域名被当成「可用」 |
| 4 | 没有国内地址兜底 | 发布页的 `comic18j-*` 完全没进代码 | 海外 CDN 被墙时没有任何退路 |
| 5 | 每台主机串行重试 + 全局 15s/35s 超时 | `_requestApi` 对每个 host 顺序 await | 7 台里前 3 台死就 >45s，首屏像卡死 |
| 6 | 探测结论不落盘 | 只有 `jm_api_hosts` 顺序，没有延迟/健康度 | 每次冷启动重新撞一遍死线路 |
| 7 | 「自动切换线路」开关没接线 | `autoSwitchHost` 只写不读 | 假开关 |

## 2. 实测数据（2026-11-15，出口：本机 FlClash 代理）

### API 线路（APP 接口，`/setting` 全链路）

| 主机 | 标签 | 状态 | 延迟 | 来源 |
|---|---|---|---|---|
| `www.cdnutc.cc` | 線路2 | ok | 6.2s | TOS `Setting`/`Server`/`jm3_Server` |
| `www.cdngwc.net` | 線路3 | ok | 6.2s | TOS + GitHub 镜像 |
| `www.cdngwc.cc` | — | ok | 6.3s | GitHub 镜像 |
| `www.cdngwc.club` | 線路4 | ok | 6.3s | TOS + GitHub 镜像 |
| `www.cdnbtd.cc` | 線路1 | ok | 8.1s | TOS |
| `www.cdnhjk.net` | — | ok | 11.3s | GitHub 镜像（波动大） |
| `www.cdnutc.me` | 線路5 | timeout | 15s+ | TOS `jm3_Server` |

> 延迟里的 ~6s 是本机代理链路固定开销，不是站点本身；真机直连/CN 出口应显著更低。

### 国内地址（发布页「內地 / 分流」）

| 域名 | 分区 | `/setting` | `/media/albums/1490702_3x4.jpg` | 结论 |
|---|---|---|---|---|
| `comic18j-susu.com` | 內地 | 404 | **200 image/jpeg 86KB** | 只能当图床 |
| `comic18j-nico.work` | 分流1 | 404 | **200 image/jpeg 86KB** | 只能当图床 |
| `comic18j-neo.com` | 分流2 | 404 | **200 image/jpeg 86KB** | 只能当图床 |

- 网页 `https://comic18j-*.com/` → 301 到 `https://18comic.vip/` → Cloudflare「Just a moment...」挑战（403）。
- 因此**国内域名不要当 API 线路用**：APP 协议只在 `www.cdn*` 上；但 `/media/...` 能直出图片，
  这是海外图床全挂时的国内兜底（`JmConstants.domesticHosts`）。
- 发布页本身：`jmcomictt.site`、`jmcomicgo.org`（镜像，解析出同一批域名）。

### 图形域名（HTML 兜底）

`18comic.ink`（200）、`18comic.vip` / `jmcomic-zzz.one` / `jmcomic-zzz.org`（Cloudflare 挑战）。
HTML 兜底顺序：API 域名 → 国际网页域名 → 国内域名。

## 3. 模块结构

```
lib/data/
├─ models/jm_host_entry.dart      # 一条线路：kind(api/image/web)、label、status、latency、domestic、sources
├─ sources/
│  ├─ jm_host_catalog.dart        # 四个源的解析：种子 JSON / 域名服务明文 / 发布页 HTML / GitHub 配置
│  ├─ jm_host_probe.dart          # 真·连通性探测：/setting（token+AES-256）、/media 封面、首页 HTML
│  ├─ jm_endpoint_resolver.dart   # 编排：并发发现 → 合并去重 → 健康度回填 → 分批实测 → 落盘 → 报告
│  └─ jm_api_client.dart          # 业务请求：按健康度轮换、单次尝试超时、失败写健康表
├─ local/endpoint_store.dart      # 线路表 + 健康表（jm_host_health）+ 排序/冷却/TTL
└─ repositories/session_repository.dart  # 设置页数据源：rediscover / probeAll / 状态文案
assets/data/jm_hosts.json         # 打进 APK 的种子（api/image/web 三组）
tools/probe_hosts.ps1             # 重新生成种子 + 报告（-Proxy / -Concurrency / -TimeoutSec）
```

## 4. 发现 → 判定 → 排序

```
refresh(force):
  并发：种子(assets) ‖ TOS×3 ‖ 发布页×2 ‖ GitHub 镜像        # 单源 6s 超时，互不阻塞
    TOS：去掉开头非 ASCII 字符 → AES-256(key=md5hex("" + domainSecret)) → Setting/Server/jm3_Server
    发布页：div.international / .southeast_asia / .china / .first_line / .second_line → span 文本
    镜像：DOMAIN_API_LIST / DOMAIN_IMAGE_LIST
  合并去重（kind|host，sources 取并集，ok 优先）
  回填种子的历史结论（按 checkedAt 写入健康表，TTL 30 分钟）
  若已有「新鲜且 ok」的线路 → 跳过探测（首屏不再等）
  否则首批 4 台并发实测（5s/台），有 ok 即停
  写线路表 + 图床表（/setting.img_host → 种子 ok → 国内 comic18j-*）
  返回报告（sources / candidates / probes / apiHosts / message）
```

判定标准（`JmHostProbe`）：

| 用途 | 请求 | 通过条件 | 失败状态 |
|---|---|---|---|
| api | `GET https://host/setting` + `token`/`tokenparam` | HTTP 200 且 `code=200` 且 AES-256 解得开且 `jm3_version`/`img_host` 至少一个非空 | `timeout` / `tls_error` / `http_4xx` / `not_json` / `code_xxx` / `decrypt_failed` / `payload_unexpected` |
| image | `GET /media/albums/1490702_3x4.jpg` | 200 且 `content-type: image/*` 且 body 非空 | `not_image` / `empty_body` / … |
| web | `GET /` | 200 且 HTML 且不是 Cloudflare 挑战页 | `cloudflare_challenge` / … |

排序（`EndpointStore`）：

1. 手填线路永远第一（用户的显式选择，不受冷却影响）；
2. 最近实测 ok 的按延迟升序；
3. 没有健康记录的（未知）；
4. 失败且还在冷却窗口内（10 分钟）→ 队尾，业务请求直接跳过（全冷却时才强试前 2 条）。

## 5. 刷新种子

```powershell
# 自动读系统代理；也可 -Proxy direct / -Proxy http://127.0.0.1:7890
pwsh -File .\tools\probe_hosts.ps1 -Concurrency 8 -TimeoutSec 15

# 产物
assets\data\jm_hosts.json                      # 打进 APK
docs\NETWORK_DOMAINS_<yyyy-MM-dd>.md           # 人读报告
```

种子是**增量**的：已存在的主机会复测并保留 `firstSeen`，新出现的 `/setting.img_host`
会被反向收编成图床候选再测一次。改完种子记得 `flutter build apk --release`。

## 6. 测试

- `test/data/jm_crypto_test.dart`：32 字节 key、.NET 侧生成的交叉密文、**真实 `/setting` 采样**（`test/fixtures/setting_envelope_live.json`）。
- `test/data/jm_host_catalog_test.dart`：四个源的解析 + 合并规则 + 打包种子自检。
- `test/data/jm_host_probe_test.dart`：ok / 403 / 解密失败 / 非 JSON / code!=200 / 图床 HTML / Cloudflare。
- `test/data/endpoint_store_test.dart`：排序、冷却、手填置顶、图床去重、清理。
- `test/data/jm_endpoint_resolver_test.dart`：多源合并、种子回填跳过探测、缓存复用、全量测速。
- `test/data/jm_api_client_rotation_test.dart`：首台返回 HTML → 自动换线、成功线路置顶、全挂报错。
- `test/manual/network_live_test.dart`：实网联调（默认 skip）：

```powershell
flutter test --dart-define=JM_LIVE=true --dart-define=JM_PROXY=http://127.0.0.1:7890 test/manual/network_live_test.dart
```

## 7. 排障

| 症状 | 先看什么 |
|---|---|
| 全线路 `decrypt_failed` | key 长度是否又变成 16 字节（本文件 §1 第 1 条） |
| 全线路 `tls_error` | 本机代理节点/证书；`--dart-define=JM_PROXY=...` 或换网络 |
| `www.cdnutc.me` 一直 timeout | 该线路波动大，属正常；健康表会自动把它排到最后 |
| 国内域名 `/setting` 404 | 预期行为：`comic18j-*` 只提供网页与 `/media`，不提供 APP 接口 |
| 设置页测速全红但能上网 | 先跑 `tools\probe_hosts.ps1 -Proxy direct`，确认是网络出口问题还是种子过期 |
| 想强制重来 | 设置页「重新探测线路」（会清健康表 + 强制重跑发现与实测） |
