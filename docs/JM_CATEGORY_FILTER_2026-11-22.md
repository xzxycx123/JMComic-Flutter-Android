# `/categories/filter` 分类筛选实测（2026-11-22）

> 背景：首页分类条（最新A漫 / 同人 / 單本 / 短篇…）点下去列表没变化。
> 结论先说：**`c` 参数只认分类 slug，传数字 id 会被服务端静默忽略。**

探测脚本：`tools/probe_categories.ps1`（md5 token + AES-256-ECB 解密，与 `tools/probe_api.ps1` 同一套协议）。
线路：`www.cdnutc.cc`，`img_host = cdn-msp2.jmapiproxy3.cc`。

---

## 1. 实测证据：`c=<数字 id>` 完全无效

同一时刻、`page=1&order=&o=mr`，只改 `c`：

| 请求 | total | 首 5 条 id | 首条分类 |
|---|---|---|---|
| `c=0` | 10000 | 1487138,1435152,624076,1356726,1433061 | 韓漫 |
| `c=1`（同人） | 10000 | **同上** | 韓漫 |
| `c=2`（單本） | 10000 | **同上** | 韓漫 |
| `c=3`（短篇） | 10000 | **同上** | 韓漫 |
| `c=4` / `c=5` | 10000 | **同上** | 韓漫 |

→ 数字 id 与未知值一样，都退回「默认榜」，所以 10 个 chip 里点哪个都一样。

## 2. 实测证据：`c=<slug>` 生效

| 请求 | total | content 里出现的分类 | 首条 |
|---|---|---|---|
| `c=doujin` | 10000 | 只有 `同人` | 1492405 |
| `c=single` | 10000 | 只有 `單本` | 1492441 |
| `c=short` | 10000 | 只有 `短篇` | 1492199 |
| `c=another` | 10000 | 只有 `其他類` | 1492390 |
| `c=hanman` | 2276 | 只有 `韓漫` | 1487138 |
| `c=meiman` | 10000 | 只有 `English Manga` | 1455559 |
| `c=another_cosplay`（Cosplay） | 9478 | 只有 `其他類`（角色扮演子类） | 1441472 |
| `c=3D` | 10000 | `其他類`+`同人`（3D 作品分布） | 1492372 |
| `c=禁漫漢化組` | 2509 | `單本`+`同人`（漢化組作品分布） | 1492210 |

注意：**大小写敏感**，`c=3d` 会退回默认榜；必须用 `/categories` 原样下发的 slug。

## 3. `/categories` 顶层分类与 slug

| id | name | slug | type | total_albums |
|---|---|---|---|---|
| 0 | 最新A漫 | *(空)* | *(空)* | 0 |
| 1 | 同人 | `doujin` | slug | 358185 |
| 2 | 單本 | `single` | slug | 43561 |
| 3 | 短篇 | `short` | slug | 120144 |
| 4 | 其他類 | `another` | slug | 53269 |
| 5 | 韓漫 | `hanman` | slug | 132374 |
| 6 | English Manga | `meiman` | slug | 397295 |
| 7 | Cosplay | `another_cosplay` | search | 0 |
| 8 | 3D | `3D` | search | 0 |
| 9 | 禁漫漢化組 | `禁漫漢化組` | search | 0 |

- `id=0` 传 `c=0` 或空串都是「不过滤」；两者返回的榜首不同（`c=0` 是默认榜，空串是纯 `/latest` 序列），
  客户端沿用 `c=0`，保持首屏不变。
- `total` 多数被服务端截到 10000；真实总数看 `/categories` 的 `total_albums`。

## 4. 排序参数 `o`

`o` 与 `c` 正交，筛选后仍然生效（`c=doujin` 下实测）：

| o | total | 说明 |
|---|---|---|
| `mr`（最新更新，默认） | 10000（截顶） | 新→旧 |
| `mv` | 10000 | 最多观看 |
| `mv_m` | 2219 | 月榜 |
| `mv_w` | 583 | 周榜 |
| `mv_t` | 52 | 日榜（1 页就到底） |
| `md` | 10000 | 最新上架 |
| `mp` | 10000 | 人气推荐 |

`order=` 这个参数留空即可（传 `order=mr` 与留空无差异）。

## 5. 子分类（漢化 / 日語 / …）：拼 `父slug_子slug`

不能单独传子类 slug，也不能用 `o=` / `filter=` / `sub_category=`（这些都被忽略）：

```
c=chinese                → 掉回全站混合流（看起来像成功，最坑）
c=doujin&o=chinese       → 父分类结果（子筛选丢失）
c=doujin_chinese         → 正确：同人 · 漢化
c=doujin_xyz（子类不存在） → 安全降级为父分类 同人
```

实测（2026-11-22）：

| `c` | total | 首 3 条 |
|---|---|---|
| `doujin` | 10000 | 1492405,1492404,1492403 |
| `doujin_chinese` | 10000 | 1492405,1492404,1492403（最新 80 条同人都属漢化） |
| `doujin_japanese` | 10000 | 1492323,1492292,1489877 |
| `single_youth`（青年漫） | 1596 | 1485385,1154471,394309 |
| `meiman_fakku` | 8870 | 1189984,1189949,1189948 |

`/categories/doujin/chinese` 返回的是网页结构 `{categories, blocks}`（blocks 为「主題A漫」标签组），
不是分页列表，别用。

## 6. 客户端修法（本次改动）

1. `JmApi.fetchFilter({page, categorySlug, order})`：`c` 直接下发 slug（`lib/data/sources/jm_api_client.dart`）。
2. `HomeRepository.fetchFeed/categoryPage/loadMore` 全部改成 `categorySlug`；分类页**不写**首页磁盘缓存，
   避免冷启动把上次点的分类当成首页（`lib/data/repositories/home_repository.dart`）。
3. `HomeFeedNotifier`：
   - 选中态改成 `(id, sub)` 记录（`selectedCategoryProvider`），`FeedKey = (category, sub, order)`；
   - `c` 由 `父slug` 或 `父slug_子slug` 拼出（`_slugFor`），子 slug 为空时不会拼出 `doujin_`；
   - 切分类只打 1 次 `/categories/filter`，轮播/分节沿用上次整页结果；失败保留外壳 + 底部重试。
4. `HomePage`：筛选态隐藏轮播与推荐分节，标题换成分类名 + 「共 N 本（10000 显示为 10,000+）· 排序」说明；
   有 `sub_categories` 时在分类条下再出二级 chip（「全部」= 只按一级分类）；空结果显示空态。
5. `JmCategoryFallback` 补上真实 slug，`/categories` 挂掉时筛选依然可用。

### 分页 / 计数注意

- `page` 超过上限会被服务端**夹到最后一页**（返回重复内容），要按 `total` 主动停；
- `total` 有 **10000 硬顶**，且与 `/categories.total_albums` 不一致（韓漫：筛选 total=2276 vs total_albums=132372），
  UI 宁可显示 `10,000+`，别拿 `total_albums` 当列表总数；
- 窗口榜（`mv_t` 同人只有 52 条）本页条数会 < 80，结束判定用 `content.length`。

验证：

```bash
flutter test test/features/home_repository_test.dart test/features/home_page_test.dart
pwsh -File tools/probe_categories.ps1            # 实网复核
```
