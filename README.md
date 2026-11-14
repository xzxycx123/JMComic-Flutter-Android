# JMComic Flutter 客户端

首页浏览（JM 移动端接口）+ 本地 PDF 下载（移植自 `D:\data\coding\JmScript`）的 Flutter 应用。
底部 Dock 三档：**首页 / 我的 / 下载**。

完整施工方案、协议规格、UI 规格、下载引擎移植对照、里程碑与测试向量 → **[PLAN.md](PLAN.md)**。

## 三段命令上手

```powershell
# 1) 目录脚手架（幂等）
pwsh -File .\tools\scaffold.ps1

# 2) 协议实网自检（线路 / promote / latest / categories / filter / album / chapter / scramble / 图床）
#    本机开着 FlClash（127.0.0.1:7890）时脚本会自动读注册表补代理；也可显式指定：
pwsh -File .\tools\probe_api.ps1
pwsh -File .\tools\probe_api.ps1 -Proxy http://127.0.0.1:7890

# 3) 装 Flutter（本机尚未安装）后生成工程并跑起来
git clone -b stable --depth 1 https://github.com/flutter/flutter.git D:\data\tools\flutter
$env:Path = 'D:\data\tools\flutter\bin;' + $env:Path
flutter config --android-sdk C:\Users\Jolie\AppData\Local\Android\Sdk
flutter create --org com.jmcomic --project-name jm_comic --platforms android,ios .
flutter pub get
flutter run
```

## 目录速查

| 路径 | 说明 |
|---|---|
| `PLAN.md` | 交接文档（协议 / UI / 移植 / 里程碑 / 测试向量） |
| `docs/ui-draft.html` | **UI 交互草稿**：六屏可点原型（首页/搜索/详情/阅读器/下载/我的）+ 25 个按钮编号 + 行为/接口对照表（浏览器直接打开） |
| `docs/ui-draft*.png` | 草稿截图（首页 / 搜索 / 详情 / 阅读器 / 下载 / 我的） |
| `assets/icons/*.svg` | 全部 UI 图标（自绘 24×24 / stroke 1.75），规则见 `assets/README.md` |
| `assets/illustrations/*.svg` | 空态 / 错误态插画 |
| `tools/check_ui_rules.ps1` | UI 守卫：禁 emoji、禁 `Icons.*`、图标必须 SVG |
| `docs/PROBE_RESULT_2026-11-14.txt` | 一次全绿的接口探测留档 |
| `lib/core` | 主题、路由、Dio、图片算法、工具 |
| `lib/data` | 模型、协议源（crypto/api/scraper/parser）、本地存储、仓储 |
| `lib/features` | shell（三 tab）、home、album、reader、mine、download |
| `lib/features/download/engine` | 下载引擎（对照 `JmScript` 的 Kotlin 实现） |
| `test` | 单元测试 + fixtures（向量来自 JmScript 单测） |
| `tools` | `scaffold.ps1` 目录脚手架、`probe_api.ps1` 协议探测 |

## 关键事实（实测，2026-11-14）

- token = `md5hex(ts + "185Hcomic3PAPP7R")`；响应 `data` 用 `AES-128-ECB/PKCS7`、key = `ASCII(md5hex(ts + "185Hcomic3PAPP7R"))[0..16]` 解密。
- `/promote`（8 模块）、`/latest`（80/页）、`/categories`、`/categories/filter`（80/页）**直接可用**，首页无需依赖 HTML 解析。
- 列表接口 `image` 字段恒空 → 封面自拼：`https://{img_host}/media/albums/{id}_3x4.jpg`（实测 200）。
- 正文图：`https://{img_host}/media/photos/{photoId}/{filename}`；切片阈值来自 `/chapter_view_template` 的 `scramble_id`。
