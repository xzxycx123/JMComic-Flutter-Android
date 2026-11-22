# dsh-subagent-models

让**子 Agent 能选的模型**从「只有父会话那一条路由」变成「你勾选过的那些」。
三个入口、一份数据、同一组操作：

| 入口 | 槽位 | 说明 |
| --- | --- | --- |
| 新建会话行的「子Agent模型 · N」 | `conversation.hero.options` | 点开就是**选择窗口**（模态弹窗） |
| 选择窗口本身 | `shell.overlay` | 全屏遮罩 + 居中卡片；点遮罩 / Esc 关闭；`pointer-events: auto` 以便在 click-through 浮层里可点 |
| 输入框下方的常驻条 | `conversation.composer.dock` | 折叠条，展开即内联同一份面板 |

窗口里列的就是**你在模型选择器里能看到的全部 provider × model**；勾选即写进 DSH 自己的
`subagent-model-selection-settings`（`enabled` + `allowedModels`），点「应用到当前会话」再把同一份白名单
写进当前会话事件 `subagent/model-selection-policy`，不用重开会话。

为什么要它：DSH 默认不给会话下策略，子 Agent 只能跟随父会话那一条路由（`list_subagent_models` 只会看到一个模型）。
把子 Agent 固定到便宜的路由，是省成本最直接的一刀。

## 组成

| 半边 | 作用 |
| --- | --- |
| `index.js`（Host） | `/subagent-models/api`（state / save / apply）+ `subagent_models` 工具；用 `ctx.llm` 读模型目录，用 `ctx.settings` 写配置，`ctx.configEditor` 读回 volatile 字段，用 `ctx.sessions` 追写会话策略 |
| `client.js`（Web） | hero 按钮 + 模态选择窗口 + composer dock 常驻条，三个入口共用 `usePicker` 与 `PickerBody`；样式全走主题 token |
| `locale/*.json` | 插件管理器里的标题与说明 |

## API

```
POST /subagent-models/api
{ "op": "state", "sessionId": "…" }
{ "op": "save",  "enabled": true, "allowedModels": [{"provider":"…","model":"…"}], "sessionId": "…" }
{ "op": "apply", "allowedModels": [{"provider":"…","model":"…"}], "sessionId": "…" }
```

Agent 侧工具：`subagent_models({ action: "list" | "save" | "apply", … })`。

## 生效范围

- 配置行只影响**之后新建的顶层会话**（DSH 的设计：策略在首次模型请求前落盘）。
- 「应用到当前会话」把同一份白名单立刻追加到当前会话，先写入者生效、不可撤销；重开会话则走配置行。

## 安装

```
plugin_manager install_bundle { "target": "<这个目录的绝对路径>" }
```

装完刷新页面即可看到 dock 里的控制条。
