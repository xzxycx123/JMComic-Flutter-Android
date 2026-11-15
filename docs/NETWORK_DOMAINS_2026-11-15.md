# JM 线路实测留档

- 生成时间：2026-11-15T11:39:10+08:00
- 网络路径：proxy:http://127.0.0.1:7890
- 采样车号：1490702（封面 /media/albums/1490702_3x4.jpg）
- 判定：api = /setting + token + AES 解密拿得到 jm3_version/img_host；image = 封面 200 且 content-type: image/*；web = 首页 200 HTML


## API 线路（APP 接口）

| 主机 | 标签 | 状态 | 延迟 | 国内 | 来源 |
|---|---|---|---|---|---|
| www.cdnutc.cc | 線路2 | ok | 6202ms |  | tos:Setting, tos:Server, tos:jm3_Server, seed, builtin |
| www.cdngwc.net | 線路3 | ok | 6214ms |  | tos:Setting, tos:Server, tos:jm3_Server, github:apiList, seed, builtin |
| www.cdnhjk.net |  | ok | 7307ms |  | github:apiList, seed, builtin |
| www.cdnbtd.cc | 線路1 | ok | 7386ms |  | tos:Setting, tos:Server, tos:jm3_Server, seed, builtin |
| www.cdngwc.club | 線路4 | ok | 7418ms |  | tos:Setting, tos:Server, tos:jm3_Server, github:apiList, seed, builtin |
| www.cdngwc.cc |  | ok | 8721ms |  | github:apiList, seed, builtin |
| www.cdnutc.me | 線路5 | timeout | 15055ms |  | tos:jm3_Server, seed, builtin |

## 图床线路（/media）

| 主机 | 标签 | 状态 | 延迟 | 国内 | 来源 |
|---|---|---|---|---|---|
| comic18j-nico.work | 分流1 | ok | 5981ms | 是 | seed, media-from:web |
| cdn-msp2.jmapiproxy2.cc |  | ok | 5987ms |  | github:imageList, seed, builtin |
| cdn-msp2.jmdanjonproxy.vip | setting:img_host | ok | 5988ms |  | setting:img_host |
| cdn-msp.jmdanjonproxy.vip | setting:img_host | ok | 5993ms |  | setting:img_host |
| www.cdnhjk.net |  | ok | 5994ms |  | seed, media-from:api |
| cdn-msp.jmapinodeudzn.net |  | ok | 5995ms |  | github:imageList, seed, builtin |
| cdn-msp2.jmapiproxy3.cc | setting:img_host | ok | 5996ms |  | seed |
| cdn-msp3.jmapiproxy3.cc | setting:img_host | ok | 5996ms |  | seed |
| cdn-msp.jmapiproxy1.cc |  | ok | 6001ms |  | github:imageList, seed, builtin |
| cdn-msp3.jmdanjonproxy.vip | setting:img_host | ok | 6001ms |  | setting:img_host |
| cdn-msp12.jmdanjonproxy.xyz | setting:img_host | ok | 6002ms |  | seed |
| cdn-msp3.jmapiproxy1.cc | setting:img_host | ok | 6003ms |  | seed |
| cdn-msp3.jmapiproxy2.cc |  | ok | 6003ms |  | github:imageList, seed, builtin |
| cdn-msp.jmapiproxy3.cc | setting:img_host | ok | 6004ms |  | seed |
| cdn-msp.jmapiproxy2.cc |  | ok | 6005ms |  | github:imageList, seed, builtin |
| comic18j-neo.com | 分流2 | ok | 6008ms | 是 | seed, media-from:web |
| www.cdngwc.net | 線路3 | ok | 6009ms |  | seed, media-from:api |
| www.cdnutc.cc | 線路2 | ok | 6011ms |  | seed, media-from:api |
| www.cdngwc.club | 線路4 | ok | 6014ms |  | seed, media-from:api |
| www.cdnbtd.cc | 線路1 | ok | 6017ms |  | seed, media-from:api |
| 18comic.ink | 國際通用 | ok | 6025ms |  | seed, media-from:web |
| cdn-msp3.jmapinodeudzn.net |  | ok | 6028ms |  | github:imageList, seed, builtin |
| cdn-msp.jmdanjonproxy.xyz | setting:img_host | ok | 6035ms |  | seed |
| www.cdngwc.cc |  | ok | 6035ms |  | seed, media-from:api |
| comic18j-susu.com | 內地 | ok | 6050ms | 是 | seed, media-from:web |

## 网页域名（HTML 兜底 / 发布页）

| 主机 | 标签 | 状态 | 延迟 | 国内 | 来源 |
|---|---|---|---|---|---|
| 18comic.ink | 國際通用 | ok | 6528ms |  | pub:https://jmcomictt.site, seed |
| jmcomic-zzz.org | 東南亞 | cloudflare_challenge | 5862ms |  | pub:https://jmcomictt.site, seed |
| jmcomic-zzz.one | 東南亞 | cloudflare_challenge | 5875ms |  | pub:https://jmcomictt.site, seed |
| 18comic.vip | 國際通用 | cloudflare_challenge | 5917ms |  | pub:https://jmcomictt.site, seed |
| comic18j-susu.com | 內地 | cloudflare_challenge | 11767ms | 是 | pub:https://jmcomictt.site, seed |
| comic18j-neo.com | 分流2 | cloudflare_challenge | 11775ms | 是 | pub:https://jmcomictt.site, seed |
| comic18j-nico.work | 分流1 | cloudflare_challenge | 11784ms | 是 | pub:https://jmcomictt.site, seed |

## 结论

- 可用 API：www.cdnutc.cc、www.cdngwc.net、www.cdnhjk.net、www.cdnbtd.cc、www.cdngwc.club、www.cdngwc.cc
- 可用图床：comic18j-nico.work、cdn-msp2.jmapiproxy2.cc、cdn-msp2.jmdanjonproxy.vip、cdn-msp.jmdanjonproxy.vip、www.cdnhjk.net、cdn-msp.jmapinodeudzn.net、cdn-msp2.jmapiproxy3.cc、cdn-msp3.jmapiproxy3.cc、cdn-msp.jmapiproxy1.cc、cdn-msp3.jmdanjonproxy.vip、cdn-msp12.jmdanjonproxy.xyz、cdn-msp3.jmapiproxy1.cc、cdn-msp3.jmapiproxy2.cc、cdn-msp.jmapiproxy3.cc、cdn-msp.jmapiproxy2.cc、comic18j-neo.com、www.cdngwc.net、www.cdnutc.cc、www.cdngwc.club、www.cdnbtd.cc、18comic.ink、cdn-msp3.jmapinodeudzn.net、cdn-msp.jmdanjonproxy.xyz、www.cdngwc.cc、comic18j-susu.com
- 可用网页：18comic.ink

> 本文件由 `tools\probe_hosts.ps1` 生成，重新跑一遍即可刷新；`assets\data\jm_hosts.json` 会被打进 APK 作为内置种子。