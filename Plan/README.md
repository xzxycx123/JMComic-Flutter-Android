# JMComic 全量 LiquidGlass 界面改造计划

> 状态：主要页面和浮层已迁移，已生成 Android Release APK；完整物理真机视觉矩阵与 profile 待验收。  
> 适用工程：`D:\data\product\JMComic`  
> 实施顺序：共享材质与控件 → 页面 → 浮层 → 阅读器 HUD → 验收。

## 本次实施记录

- 新增统一材质 Scope 与共享组件，覆盖 Dock、首页、搜索、详情与评论、下载与历史、我的与设置、收藏、登录、关于，以及漫画和 PDF 阅读器 HUD。漫画、PDF 正文与封面图未加折射。
- Metal 仍为默认材质，沿用原 Hive 设置键。测试覆盖即时切换、分支滚动和输入保留、详情开始阅读与续读、检索历史逐条删除、窄屏与放大字体、浮层返回、Toast 与阅读器滑杆。
- 基线：静态分析通过，156 项测试通过、2 项实网测试默认跳过，Release APK 构建通过。保留同一 Android 测试环境的 Metal 截图。
- 发布验收：静态分析无问题，173 项自动测试通过、2 项实网测试按默认设置跳过；SVG 守卫、差异检查与 Release APK 构建通过。Android 15 模拟环境已验证发布包启动、从 Metal 切换到 LiquidGlass、浅色与深色主题显示，以及冷启动保留 LiquidGlass。
- 发布产物：`build/app/outputs/flutter-apk/app-release.apk`（约 68.4 MB）。下方未勾选的真机矩阵、中文输入法、横竖屏完整走查和 profile 帧耗时不计入本次已验证结果。

---

## 0. 一句话目标

在保留现有 **Metal / LiquidGlass** 设置、**Metal 默认**以及浅色/深色模式的前提下，把 LiquidGlass 从“只有 Dock 玻璃化”扩展为完整的界面材质：**标签、分类、按钮、输入框、卡片、工具栏、开关、滑杆、菜单、弹窗、Toast 与阅读器 HUD 全部统一为 iOS 27 风格 LiquidGlass**，业务行为不变。

首批肉眼验收项：

- 详情页“开始阅读 / 继续阅读”是带品牌橙强调、按压回弹与玻璃光影的主按钮。
- 首页分类、排序、搜索历史、详情标签、下载状态等 chips/tags 全部玻璃化。
- Metal 模式仍显示当前界面，默认设置及持久化逻辑不变。

---

## 1. 已确认的工程现状

| 项目 | 当前状态 | 本次处理 |
|---|---|---|
| 玻璃依赖 | `liquid_glass_widgets: 1.19.0` 已接入 | 不新增同类 UI 依赖 |
| 初始化 | `lib/main.dart` 已初始化玻璃着色器 | 保留 |
| 根主题 | `lib/app.dart` 已使用 `LiquidGlassWidgets.wrap` + `GlassThemeData.ios27()` | 保留并补全品牌 token 与材质 Scope |
| 设置模型 | `AppInterfaceStyle.metal/liquidGlass` 已存在 | 不修改 Hive key，不新增设置项 |
| 默认材质 | Metal | 保持不变 |
| 材质持久化 | `interfaceStyle` 已写入 Hive | 保持不变 |
| Dock | LiquidGlass 已使用 `GlassScaffold + GlassTabBar.bottom` | 保留并纳入统一 token |
| 其他页面 | 仍大量直接使用 Material 按钮、chips、输入框、Dialog、BottomSheet 等 | 通过共享适配组件逐步替换 |
| 图标规则 | 业务代码只允许 `SvgIcon` / SVG 资源 | 继续强制执行，不使用插件默认字体图标 |
| 阅读器 | 正文恒深色，手势、缩放、预取与进度逻辑已稳定 | 只改 HUD 与控件，不动正文和状态机 |

### 1.1 本次不做的事

- 不修改 API、下载、收藏、阅读进度、账号会话等业务逻辑。
- 不修改 `AppInterfaceStyle` 的 Hive 存储值，避免影响已有用户设置。
- 不把 LiquidGlass 改成默认材质，不删除 Metal。
- 不对漫画正文、PDF 页面、封面图片本身做折射或扭曲。
- 不用全屏强滤镜假装 LiquidGlass；交互控件必须使用真实的玻璃材质、按压反馈与层次。
- 不在每张滚动卡片上创建独立 premium shader layer。
- 不为了玻璃化改变现有路由、按钮文案、点击结果或页面信息架构。

---

## 2. 总体设计决策

### 2.1 两种材质共用一套业务组件

所有业务页面只调用 `AppButton`、`AppChip`、`AppSurface` 等共享组件：

```text
业务页面
   │ 同一组参数、回调、语义标签
   ▼
共享 App* 适配组件
   │ 读取 InterfaceStyleScope
   ├─ metal       → 当前 Material 实现
   └─ liquidGlass → liquid_glass_widgets 实现
```

这样可以保证：

1. Metal 不被全局玻璃样式污染。
2. 页面不需要分别维护两套点击逻辑。
3. 后续调整玻璃参数只改共享组件，不再逐页返工。
4. 测试可以分别覆盖两种材质下的同一行为契约。

### 2.2 材质状态数据流

```text
Hive interfaceStyle
        ↓
SettingsNotifier / settingsProvider
        ↓
interfaceStyleProvider
        ↓
JmComicApp 监听并重建 InterfaceStyleScope
        ↓
页面、Dialog、BottomSheet、Menu、Toast Overlay
        ↓
App* 组件选择 Metal 或 LiquidGlass 分支
```

实施要求：

- `JmComicApp` 直接 watch `interfaceStyleProvider`。
- `InterfaceStyleScope` 放在 `MaterialApp.router` 的 `builder` 内、Navigator 外，确保路由页面和 Overlay 都能读取。
- `LiquidGlassWidgets.wrap` 与 `brightnessResolver: Theme.maybeBrightnessOf` 保留。
- `InterfaceStyleScope.of(context)` 返回明确材质；`maybeOf` 缺省时回退 Metal，保证独立 widget 测试稳定。
- `updateShouldNotify` 只比较材质值，切换时即时更新，不重建 Hive、不重置路由。

### 2.3 玻璃视觉原则

- 使用 `GlassThemeData.ios27()` 作为基础，不自行发明另一套玻璃风格。
- 品牌橙用于主按钮、选中态、焦点与进度，不大面积铺满背景。
- 浅色和深色都从当前 `ColorScheme` 派生玻璃 tint、文字、描边和辉光；业务 widget 不写死 hex。
- 玻璃层次分为：页面背景 → 非折射内容 surface → 玻璃控件 → Overlay。避免每一层都强折射。
- 标签文字、按钮文字和正文必须清晰，不能为了折射牺牲对比度。
- 动效以轻微压缩、回弹、选中透镜移动和光影变化为主，不增加影响操作的长时间动画。
- 尊重减少动态效果与无障碍语义；禁用态不仅是降低透明度，还要真正截断点击。

---

## 3. 计划新增的共享结构

```text
lib/
├─ core/
│  ├─ theme/
│  │  ├─ interface_style_scope.dart   # InheritedWidget + BuildContext 扩展
│  │  └─ app_glass_theme.dart         # iOS 27 token、亮度、玻璃参数与降级规则
│  └─ ui/
│     └─ glass/
│        ├─ app_glass.dart            # 仅做共享组件 export
│        ├─ app_button.dart
│        ├─ app_chip.dart
│        ├─ app_segmented_control.dart
│        ├─ app_icon_button.dart
│        ├─ app_surface.dart
│        ├─ app_list_tile.dart
│        ├─ app_text_field.dart
│        ├─ app_search_bar.dart
│        ├─ app_switch.dart
│        ├─ app_slider.dart
│        ├─ app_progress_indicator.dart
│        ├─ app_badge.dart
│        ├─ app_dialog.dart
│        ├─ app_sheet.dart
│        ├─ app_menu.dart
│        └─ app_glass_page.dart       # 页面背景、共享 layer 与滚动质量配置
```

文件名允许因 Dart lint 做纯格式调整，但不要改变职责边界，也不要把这些组件重新塞回各个 feature。

---

## 4. 共享组件 API 与行为契约

### 4.1 `InterfaceStyleScope`

公开能力：

- `AppInterfaceStyle style`
- `static AppInterfaceStyle of(BuildContext context)`
- `static AppInterfaceStyle maybeOf(BuildContext context)`，无 Scope 时回退 Metal
- `context.interfaceStyle`
- `context.isLiquidGlass`

不公开任何写设置方法；设置仍由现有 `SettingsNotifier.setInterfaceStyle()` 负责。

### 4.2 `AppButton`

覆盖“开始阅读”、下载、登录、重试、发送评论、确认、取消等全部按钮。

公共参数：`label/child`、SVG `leadingIcon/trailingIcon`、`onPressed`、`variant`、`loading`、`expanded`、尺寸与 `semanticLabel`。

`variant` 固定为 `primary / secondary / text / destructive`：

| 状态 | Metal | LiquidGlass |
|---|---|---|
| primary | 当前 `FilledButton` | `GlassButton.custom` + 品牌橙 tint/glow + 高对比前景 |
| secondary | 当前 `OutlinedButton` | 低强调玻璃、细描边 |
| text | 当前 `TextButton` | 透明或极轻玻璃，保留至少 44×44 触控区 |
| destructive | 当前错误色按钮 | 错误色 tint/glow，不只依赖文字颜色 |
| loading | 原加载指示且禁止重复提交 | 统一小玻璃进度，禁止点击 |
| disabled | 原禁用样式 | 降低玻璃与文字强调，`onTap` 不执行 |

“开始阅读”保持主 CTA 高度 48、播放 SVG、单行省略和现有 `_openReader` 回调；“下载”保持次按钮和 108 宽布局。只换材质，不改操作条结构。

### 4.3 `AppChip` / `AppBadge`

公共能力：文本、可选 SVG leading icon、`selected`、`onTap`、`onDeleted`、`enabled`、语义标签、颜色与 padding。

- 可点击分类、排序、历史和文件夹 → `GlassChip`。
- 纯展示标签/状态 → `GlassChip(enabled: true)`，不传点击回调，保持静态语义。
- 数字计数和小角标 → `GlassBadge`；状态色沿用 `ColorScheme`。
- 删除按钮显式传 `SvgIcon(AppIcons.close)`；**不得使用 `GlassChip` 默认的 `CupertinoIcons.xmark_circle_fill`**。
- 首页分类维持横向列表和 32–38px 视觉高度；光晕不能扩大布局或遮挡相邻 chip。

### 4.4 `AppSegmentedControl<T>`

公共模型：

```text
AppSegment<T>(value, label, icon?, semanticLabel?)
AppSegmentedControl<T>(segments, selected, onChanged, scrollable = false)
```

- Metal 返回当前 `SegmentedButton<T>` 行为。
- LiquidGlass 将 value 映射为 index，使用 `GlassSegmentedControl`；空间不足时使用 scrollable 变体。
- 点击后把 index 还原成原始泛型 value，禁止页面维护第二套选中状态。
- 选中透镜不能裁切；不放入折射型玻璃卡片。
- `InterfaceStyleSelector` 同样接入，从 LiquidGlass 切回 Metal 时必须立即可点。

### 4.5 `AppSurface` / `AppListTile`

| surfaceKind | 用途 | LiquidGlass 实现 |
|---|---|---|
| content | 资料卡、二维码卡、纯内容卡 | `GlassContainer.card`，标准质量 |
| controlGroup | 内含按钮、Switch、Slider、Segmented 的设置组 | `GlassGroupedSection` 或非折射 surface，禁止 glass-in-glass |
| overlay | Toast、菜单、弹层内容 | 独立 Overlay layer + 玻璃 surface |

- 卡片点击、长按、Hero 和图片内容不变。
- 任务卡按 `controlGroup` 处理，避免内部菜单、进度和取消按钮受折射父层影响。
- 列表项保留高度、分隔、省略和进度文字。
- 滚动列表统一 `GlassQuality.standard` 或 lightweight，禁止逐卡片 `useOwnLayer: true + premium`。

### 4.6 输入与搜索

`AppTextField` 保留当前用到的 controller、focusNode、placeholder、obscureText、键盘类型、提交/变更回调、enabled/readOnly、autofocus、minLines/maxLines/maxLength、formatters、autofillHints 和前后缀。

Metal 保留 `TextField` 与 decoration；LiquidGlass 使用 `GlassTextField`。搜索统一 `AppSearchBar`，保留车号识别、回车搜索、取消和清空。密码可见性与清除图标使用 SVG，焦点、文本选择和中文输入法需真机验收。

### 4.7 Switch、Slider 与进度

- `AppSwitch`：Metal 使用当前 `Switch`，LiquidGlass 使用 `GlassSwitch`；设置写入时机不变。
- `AppSlider`：Metal 使用当前 `Slider`，LiquidGlass 使用 `GlassSlider`。
- 阅读器仍是“拖动只更新预览页，松手才跳页并落盘”，禁止把 `onChanged` 接回实时翻页。
- `AppProgressIndicator` 映射 `GlassProgressIndicator.circular/linear`。
- 骨架屏使用轻量半透明色块与现有 shimmer，不给每块骨架创建折射层。

### 4.8 Dialog、Sheet、Menu 与 Toast

- `AppDialog.show<T>`：Metal 继续 `showDialog + AlertDialog`；LiquidGlass 使用 `GlassDialog.show<T>`。操作保持 1–3 个，返回值不变。
- 输入 Dialog 使用 `AppTextField`，不混用未适配输入框。
- `AppSheet.show<T>`：Metal 继续 `showModalBottomSheet`；LiquidGlass 使用 `GlassModalSheet.show<T>`，保留 SafeArea、滚动与键盘 inset。
- 线路、主题、阅读模式、文件夹和历史操作统一走 `AppSheet`。
- 下载任务菜单走 `AppMenu`，LiquidGlass 使用 `GlassPullDownButton`/`GlassMenu`，值映射不变。
- `AppToast` 保留当前 Overlay + 自管 Timer + 进出场动画，避免 SnackBar 永不消失的问题。
- LiquidGlass Toast 只替换视觉 surface；有“撤销”时延长停留并可点，无操作时继续点击穿透。
- 散落 `ScaffoldMessenger.showSnackBar` 统一迁移 `AppToast`，不改时长和文案。

### 4.9 AppBar 与页面背景

- 普通二级页使用共享 `AppGlassPage`/玻璃 pinned chrome。
- 首页保留 `CustomScrollView`、粘性分类和滚动行为，以玻璃 pinned chrome 替换纯色栏，不强改 Sliver 架构。
- 详情保留 260 高模糊封面头和 `SliverAppBar`；返回、收藏、分享及折叠工具栏玻璃化。
- LiquidGlass 沿用当前品牌渐变，Metal 背景不变。
- 阅读器和 PDF 阅读器正文继续恒深色。

---

## 5. 页面迁移清单

### 5.1 壳体与全局反馈

- [ ] `lib/app.dart`：监听材质、注入 Scope，保留 iOS 27 根主题。
- [ ] `lib/features/shell/shell_page.dart`：复用统一背景与 token，Dock 路由逻辑不动。
- [ ] `lib/features/shell/glass_nav_bar.dart`：颜色、文字、动效改读共享 token。
- [ ] `lib/core/theme/interface_style_selector.dart`：外壳、分段控件和 iOS 27 标识适配。
- [ ] `lib/core/ui/app_toast.dart`：统一玻璃 Toast 与操作按钮。

### 5.2 首页

涉及 `home_page.dart`、`category_chips.dart`、`sort_chips.dart`、`hero_banner.dart`、`section_header.dart`、`album_card.dart`、`feed_skeleton.dart`。

- [ ] 顶部图标按钮与滚动工具栏玻璃化。
- [ ] 分类/排序 chips 使用 `AppChip`，保留 PNG 榜单角标与原 provider。
- [ ] 轮播徽标和指示点使用轻量玻璃/`GlassPageControl`。
- [ ] “更多”、重试和错误态按钮使用 `AppButton`。
- [ ] 本子卡片外壳与分类标签玻璃化，封面本身不折射。
- [ ] 无限流、刷新、缓存、滚动位置与分页逻辑不变。

### 5.3 搜索

涉及 `search_page.dart`、`search_field.dart`、`result_grid.dart`。

- [ ] 搜索输入、取消、清空和视图切换适配。
- [ ] 搜索历史与排序 chips 适配，删除图标使用 SVG。
- [ ] 结果计数、加载更多、空态/错误态按钮和进度适配。
- [ ] 车号直达、关键词搜索、历史写入和分页逻辑不变。

### 5.4 详情与评论

涉及 `album_page.dart`、`chapter_tile.dart`、`comment_section.dart`。

- [ ] 返回、收藏、分享、点赞、评论按钮玻璃化。
- [ ] tags、统计、状态和“剧透”标签玻璃化。
- [ ] **“开始阅读 / 继续阅读”和“下载”接入 `AppButton`。**
- [ ] 章节列表项和阅读进度标签适配。
- [ ] 评论输入、发送、回复、加载更多、剧透开关及 Dialog/Sheet 适配。
- [ ] 收藏撤销、点赞乐观更新、阅读恢复和下载跳转不变。

### 5.5 阅读器与 PDF 阅读器

涉及 `reader_page.dart`、`reader_hud.dart`、`pdf_viewer_page.dart`。

- [ ] 顶部返回、标题、线路和阅读模式控件玻璃化。
- [ ] 底部进度、百分比和 Slider 玻璃化。
- [ ] 线路/模式 Sheet、重试和错误提示适配。
- [ ] HUD 使用独立轻量玻璃层，保留 SafeArea。
- [ ] 阅读器始终深色，玻璃 tint 不随浅色主题洗白正文。
- [ ] 点击分区、双指缩放、双击、双指锁翻页、预取和进度落盘不变。
- [ ] PDF 渲染、平台通道和文件打开逻辑不变。

### 5.6 下载与历史

涉及 `download_page.dart`、`history_page.dart`、`download_input.dart`、`task_card.dart`。

- [ ] 批量输入卡、粘贴、清空和“加入队列”适配。
- [ ] 下载/历史筛选分段控件适配。
- [ ] 任务卡、状态胶囊、进度、取消和溢出菜单适配。
- [ ] 删除确认、清空历史、打开 PDF、重试等反馈适配。
- [ ] 下载队列、通知、取消、重试和文件记录行为不变。

### 5.7 我的、设置、收藏、登录与关于

涉及 `mine_page.dart`、`settings_page.dart`、`read_history_page.dart`、`about_page.dart`、`collect_page.dart`、`login_page.dart`。

- [ ] 资料卡、账号卡、统计、设置分组和列表项适配。
- [ ] 明暗模式、阅读模式、线路、阅读历史等 Sheet 适配。
- [ ] 自动切换、翻页动画、记住密码等 Switch 适配。
- [ ] 线路测速、手动域名、缓存清理、导出记录等按钮与反馈适配。
- [ ] 收藏文件夹 chips、创建/删除/同步 Dialog 与 Sheet 适配。
- [ ] 登录输入、密码可见性、结果 Dialog 和加载按钮适配。
- [ ] 阅读历史进度、删除与清空操作适配。
- [ ] 关于页二维码卡、许可与链接操作适配。

---

## 6. 分阶段施工顺序

### M0 — 基线冻结

- [x] 记录 `flutter analyze`、`flutter test` 和 APK 构建基线。
- [x] 搜索盘点所有 Material 控件及 Overlay，迁移完成时再次对照。
- [x] 截取 Metal 关键页面作为回归基准。

### M1 — 材质 Scope、token 和共享组件骨架

- [ ] 新建 `InterfaceStyleScope` 并接入根节点。
- [ ] 新建 `app_glass_theme.dart`，集中 iOS 27、品牌色、明暗主题和质量参数。
- [ ] 新建 `app_glass_page.dart`，提供共享背景/layer。
- [ ] 建立共享组件 export 与双材质测试夹具。

完成标准：普通路由、Dialog、Sheet 和 Toast 均能读到正确材质；Metal 无视觉变化。

### M2 — 按钮、标签、分段控件优先落地

- [ ] 完成 `AppButton`、`AppIconButton`、`AppChip`、`AppBadge`、`AppSegmentedControl`。
- [ ] 首先迁移详情“开始阅读/继续阅读”和首页分类、排序、详情 tags。
- [ ] 再迁移其余按钮、搜索历史、文件夹和筛选器。

完成标准：用户点名的控件全部有真实玻璃质感；点击、禁用、加载、选中与静态标签测试通过。

### M3 — Surface、输入和主页面

- [ ] 完成 `AppSurface`、`AppListTile`、输入、搜索、Switch、Slider、进度组件。
- [ ] 迁移首页、搜索、详情、下载、收藏、我的、设置、登录和关于。
- [ ] 清理各页面私有玻璃容器与重复参数。

完成标准：除阅读器特殊 HUD 外，普通页面完成材质覆盖；Metal 回归测试通过。

### M4 — Overlay 与反馈统一

- [ ] 完成 `AppDialog`、`AppSheet`、`AppMenu` 和玻璃 Toast。
- [ ] 替换直接 `AlertDialog`、`showModalBottomSheet`、任务菜单和散落 SnackBar。
- [ ] 验证 `context.mounted`、返回泛型值和重复关闭行为。

完成标准：二级页面及浮层无突兀 Material 纯实色控件，Toast 仍可靠自动消失。

### M5 — 阅读器与 PDF 特殊收口

- [ ] 玻璃化两套 HUD、Slider、线路与模式选择。
- [ ] 验证手势、缩放、进度预览和 SafeArea。
- [ ] 对滚动页面和阅读器做真机 profile，必要时降低共享 layer 质量，不改业务逻辑。

### M6 — 全量审计、性能与发布

- [ ] 重新扫描 Material 控件；除共享适配组件的 Metal 分支外，业务页面无遗漏。
- [ ] 检查无玻璃嵌套、无逐卡片 premium layer、无默认 Cupertino 图标。
- [ ] 跑完整自动测试、UI 规则、Release 构建与真机矩阵。
- [ ] 更新本文件勾选状态和最终验证结果。

---

## 7. 渲染与性能硬约束

1. **共享 layer**：以页面、独立 Overlay 或局部工具区复用，不为每个 chip/card 建独立高成本 layer。
2. **滚动质量**：网格、横滑分节、长列表使用 `GlassQuality.standard` 或 lightweight；premium 仅用于少量静态关键控件，并需 profile 证明可接受。
3. **禁止嵌套折射**：玻璃按钮、Slider、Switch、Segmented 不放入折射型 `GlassContainer.card`；父组采用 `GlassGroupedSection` 或非折射 surface。
4. **避免裁切**：果冻拉伸、选中透镜和 glow 的父级 clip 必须检查。
5. **公开适配路径**：使用 `AdaptiveGlass` 和公开 Glass widgets，不直接使用仅限 Impeller 的底层 `LiquidGlass`，避免 Skia/Web 空白。
6. **正文优先**：漫画/PDF 图片不做 backdrop capture 或折射；HUD 隐藏后不留额外 shader 开销。
7. **降级顺序**：先降低模糊/质量，再减少 glow/色差，最后将长列表卡片改成非折射 surface；按钮、标签和 Dock 的玻璃交互不能全部撤掉。
8. **对比度优先**：背景过花时提高 surface tint 或文字 scrim，不以加粗全部文字掩盖问题。

---

## 8. 边界情况清单

| 场景 | 必须保证 |
|---|---|
| Metal ↔ LiquidGlass 即时切换 | 当前路由、Tab、滚动位置、输入和阅读页码不丢失 |
| 冷启动 | 默认/恢复 Hive 材质，无先 Metal 后 Glass 的大面积闪烁 |
| 浅色/深色/跟随系统 | 文字、图标、选中态和描边清晰，明暗与材质解耦 |
| 阅读器 | 始终深色，HUD 与正文有足够对比度 |
| 禁用/加载 | 不可重复点击，进度和 Semantics 状态正确 |
| 静态标签 | 不被读屏误认为按钮，不响应无意义点击 |
| destructive 操作 | 错误色和确认流程保留，返回值正确 |
| 长中文/长标题 | 原省略规则不变，按钮不被图标挤出 |
| 字体放大 1.3 | CTA、chips、设置项、Dialog、HUD 无溢出 |
| 横竖屏/窄屏 | 分段控件可滚动或合理换行，底部 CTA 不重叠 |
| SafeArea | Dock、Toast、Sheet、HUD 不碰系统手势区和状态栏 |
| 键盘 | 登录、搜索、评论、下载输入可见，Sheet 可滚动 |
| 减少动态效果 | 减弱非必要拉伸与辉光，功能状态仍可辨认 |
| SVG 规则 | 删除、关闭、返回、下拉等不采用插件默认字体图标 |
| 异步 Overlay | 页面销毁后不使用失效 context，不重复 pop |

---

## 9. 测试计划与 Definition of Done

### 9.1 新增自动测试

```text
test/core/ui/glass/app_button_test.dart
test/core/ui/glass/app_chip_test.dart
test/core/ui/glass/app_segmented_control_test.dart
test/core/ui/glass/app_surface_test.dart
test/core/ui/glass/app_overlay_test.dart
test/features/liquid_glass_components_test.dart
```

- [ ] 共享组件在 Metal 与 LiquidGlass 下选择正确实现。
- [ ] 点击、长按、禁用、加载、选中、删除和泛型 value 回调正确。
- [ ] “开始阅读”进入阅读器，“继续阅读”恢复当前页。
- [ ] 分类、排序、搜索历史、文件夹和筛选器仍更新原 provider。
- [ ] Dialog/Sheet 返回原值，destructive 确认流程不变。
- [ ] Toast 自动消失、撤销可点、无操作时可穿透。
- [ ] 阅读器 Slider 仍是松手跳页，双指手势不被玻璃层拦截。
- [ ] 扩展 `shell_page_test.dart`，验证普通页面和 Overlay 同步切换材质。
- [ ] 现有 Metal、设置默认值/持久化和 UI 规则测试继续通过。

自动测试以语义、组件类型和交互为主；shader 视觉用真机截图与 profile 验收，不依赖脆弱的大面积 golden。

### 9.2 真机视觉矩阵

| 页面 | 浅色 LiquidGlass | 深色 LiquidGlass | Metal 回归 |
|---|---|---|---|
| 首页与分类/排序滚动 | [ ] | [ ] | [ ] |
| 搜索与历史 chips | [ ] | [ ] | [ ] |
| 详情标签与开始阅读 | [ ] | [ ] | [ ] |
| 评论与弹层 | [ ] | [ ] | [ ] |
| 阅读器/PDF HUD | 恒深色 [ ] | 恒深色 [ ] | [ ] |
| 下载与历史 | [ ] | [ ] | [ ] |
| 收藏文件夹 | [ ] | [ ] | [ ] |
| 我的与设置 | [ ] | [ ] | [ ] |
| 登录/关于/阅读历史 | [ ] | [ ] | [ ] |

每页同时检查触控、文字对比度、1.3 倍字体、键盘、SafeArea、长列表滚动和返回后状态。

### 9.3 性能验收

- [ ] 使用 `flutter run --profile` 在同一设备对比首页长列表、搜索网格、详情和阅读器。
- [ ] 记录设备、页面、玻璃质量与帧耗时；持续 jank 时按第 7 节降级。
- [ ] 确认没有每卡片独立 premium layer，没有隐藏 HUD 持续占用高成本渲染。
- [ ] Release 模式再次走查，不以 debug/profile 结果代替最终包。

### 9.4 最终命令

```powershell
flutter analyze
flutter test
pwsh -File .\tools\check_ui_rules.ps1
flutter build apk --release
git diff --check
```

产物：`build/app/outputs/flutter-apk/app-release.apk`

### 9.5 完成定义

- [ ] LiquidGlass 覆盖所有页面、二级路由和 Overlay，不再只是 Dock。
- [ ] 所有标签和“开始阅读/继续阅读”等按钮均为统一 iOS 27 玻璃风格。
- [ ] Metal 默认、切换、持久化和原有视觉/行为保持。
- [ ] 浅色/深色、阅读器恒深色、SVG 图标规则全部满足。
- [ ] 无玻璃嵌套导致的折射失效、动画裁切或触控问题。
- [ ] 业务逻辑、路由状态、阅读进度、下载和收藏行为无回归。
- [ ] 自动测试、UI 守卫、静态检查、Release 构建和真机矩阵全部通过。

---

## 10. 最终人工走查脚本

1. 冷启动确认默认/上次材质正确，在“我的 → 外观 → 界面材质”切到 LiquidGlass。
2. 回首页滚动三页，切换分类和排序，观察 chips、卡片、工具栏与帧率。
3. 搜索关键词并删除一条历史，进入详情，检查 tags、收藏、分享和评论弹层。
4. 点击“开始阅读”，切阅读模式、拖动进度、双指缩放、切换线路，再退出确认进度恢复。
5. 回详情点击下载，检查任务进度、取消、重试、菜单和完成后打开 PDF。
6. 操作收藏文件夹、阅读历史、设置开关、线路测速、缓存清理和登录 Dialog。
7. 在每一步切换浅色/深色，抽查 1.3 倍字体与横竖屏。
8. 切回 Metal，重复关键路径，确认当前旧版界面与行为完整保留。
