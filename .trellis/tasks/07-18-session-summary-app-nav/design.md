# Design: 会话摘要与 App 导航重设计

## Overview

单任务串行交付两类改动：

1. **监控端**：Claude / Codex 从用户输入提取**短摘要**，写入既有 `message` 字段；状态变更时保留摘要。
2. **Android**：底栏三页（首页 / 设备 / 设置）+ 设备详情；视觉按 new-api default 控制台气质做 Material3 转译；主题跟随系统。

不改破坏性 API 形状；不新增历史页；不做远程操控。

## Boundaries

| 层 | 职责 | 不负责 |
|----|------|--------|
| `internal/monitor` | 摘要生成、状态机、session 快照 | UI |
| 服务端 / store | 透传 `message`、状态变更通知 | 摘要逻辑 |
| Android | 导航、过滤活跃、展示摘要、通知文案 | 解析 prompt |

## Data contract

继续用 `apitypes.Session.message`：

- **语义升级**：优先为「本轮用户任务短摘要」；无摘要时可为状态标签（permission request 等）
- **display_name**：仍为 `basename(cwd)`（无 cwd 时退回 session_id 短串）
- **隐私**：摘要限长（建议 **48 runes**）；禁止上报/日志写入完整 `user_prompt` / 对话正文
- **docs**：更新 `docs/api.md` / `docs/deploy.md` 中 message 语义说明（仍禁止全文）

通知正文约定：

```text
{machine} · {agent} · {display_name} — {message}
```

有摘要时用户能同时看到目录与任务。

## Summary rules（共享）

新增小工具函数（如 `monitor.ShortSummary(text string, maxRunes int) string`）：

1. Trim 空白
2. 取首行（遇 `\n` 截断）
3. 压缩连续空白为单空格
4. 按 rune 截断到 `maxRunes`，超长加 `…`
5. 空输入 → 空字符串（调用方回退标签）

## Claude path

### Hook 输入

`HookEvent` 扩展解析字段：

- 已有：`hook_event_name`, `session_id`, `cwd`, …
- 新增：`user_prompt`（UserPromptSubmit）

### 状态与 message

| 事件 | state | message |
|------|-------|---------|
| UserPromptSubmit | working | `ShortSummary(user_prompt)`；空则保持旧摘要或空 |
| PermissionRequest | confirm | 保留旧摘要；若无摘要可用短标签 `permission request` |
| Notification | confirm | 同上，标签 `notification` |
| Stop / SubagentStop | done | **保留旧摘要**（不要再写成 `stopped`） |
| SessionStart | idle | 可清空或保留（推荐新 session 无历史则空） |
| SessionEnd | idle | 可保留摘要供短暂可见，或清空；首页不展示 idle 即可 |
| 其他工具类 | working | **保留旧摘要** |

关键修复：当前 `ApplyHookEvent` 每次整表覆盖，`Stop` 会把 `message` 打成 `stopped`，导致摘要丢失。应：

1. 读出已有 session（若有）
2. 更新 state / display_name / updated_at
3. 仅在 UserPromptSubmit 且摘要非空时覆盖 message；否则保留 prev.Message（无 prev 再用事件标签）

## Codex path

### 文件 rollout / watcher

在 `user_message` 分支：

- 从 payload 取正文：尝试常见键 `message` / `text` / `content`（string）；若为 content 数组则拼接 text 段
- `s.message = ShortSummary(...)`；失败则保留旧摘要或 `user_message` 标签
- **tool/confirm/complete 等事件**：不要用事件名覆盖已有摘要（与 Claude 同样「保留摘要」策略）
  - 例外：若当前无摘要，confirm 仍可用短事件标签便于通知

### App-server 路径

若 thread 事件带用户输入文本，同样走 `ShortSummary`；无文本则不破坏已有 message。

### 日志

Info 日志只打截断后的 `说明=message`（已是短摘要）；**禁止**把 raw prompt 写入 slog。

## Android IA

```
BottomNav
├── 首页 Home          // 跨设备非 idle 会话，按 confirm>working>done 排序
├── 设备 Devices       // 全部机器
└── 设置 Settings      // URL / key / 通知红黄绿

Devices → DeviceDetail // 该机会话；活跃在上，idle 默认折叠
Home item click → DeviceDetail（可选带 session 高亮）
```

### 活跃定义

- 首页：`state != idle`
- `done` 自然停留依赖服务端/监控约 10 分钟降 idle；App 不做第二套计时
- SessionEnd → idle 后首页立即消失

### UI 风格（new-api → Compose）

| new-api 气质 | Compose 落地 |
|--------------|--------------|
| 干净控制台卡片 | `Card` + 适中间距、浅分割 |
| 状态标签 | `AssistChip` / 色条 + 文案（需确认/工作中/已完成/空闲） |
| 主副标题 | 主：摘要（空则 displayName）；副：`displayName · agent · machine` |
| light/dark | `isSystemInDarkTheme()` + Material3 scheme（可定制 primary 偏蓝/青，贴近控制台） |
| 顶栏状态 | 连接中/已连接/错误，一行即可 |
| 设置独立 | 底栏第三页；首次未配置可全屏引导 |

不引入 WebView，不复刻 Semi/Tailwind 组件名。

### 通知

`Notifier`：

- title：状态中文（需确认/工作中/已完成）
- text：`machine · agent · displayName — message`（message 为空则省略破折号段）

### 依赖

优先 `navigation-compose` + Material3；若工程尚未引入 navigation，在 `android/app/build.gradle.kts` 增加合理版本，与现有 Compose BOM 对齐。

## Compatibility

- 旧监控未升级时：`message` 仍是标签，App 仍可用，只是摘要为空
- 新监控 + 旧 App：列表多显示摘要文字，无害
- SQLite `message` 列已存在，无需 migration

## Trade-offs

| 选择 | 理由 | 代价 |
|------|------|------|
| 复用 `message` | 零契约破坏 | 语义从「状态标签」变为「摘要优先」 |
| 不扫进程 PID | 多会话不可靠 | 真结束依赖 SessionEnd / 超时 |
| 单任务不拆 | 串行验收简单 | 中间态 PR 可能较大 |
| 不做历史页 | 控范围 | 事后回看仍靠以后迭代 |

## Rollback

- 监控：回退 hook/摘要逻辑后，行为回到标签 message
- App：可独立回退导航 UI；契约向后兼容
- 无需数据迁移回滚

## Test focus

- `ShortSummary` 截断、首行、空串
- Claude：UserPromptSubmit 写摘要 → Stop 仍保留 → SessionEnd idle
- Codex：user_message 带正文 → 摘要；后续 task_complete 不覆盖摘要
- Android：单元/UI 若成本高，至少编译通过 + 手动验收清单（implement.md）
