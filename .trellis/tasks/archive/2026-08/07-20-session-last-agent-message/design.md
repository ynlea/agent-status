# Design：Agent 最后消息采集与展示

## 数据字段

在 `apitypes.Session` 增加（json omitempty）：

```text
last_assistant_message string  // Agent 最后一条可见文本，已截断
cwd                    string  // 完整项目路径（绝对路径），详情页展示用
```

保留现有：

```text
message        // 用户意图/状态摘要（卡片标题优先）
display_name   // 卡片短名：可继续用路径 basename，避免列表过长
state / agent / session_id / source / updated_at / machine_*
```

约定：

| 字段 | 列表卡片 | 会话详情 |
|------|----------|----------|
| `message` | 标题 | 头部副标题「用户意图」 |
| `display_name` | 次行短路径 | 可不重复展示 |
| `cwd` | 不展示（太长） | **完整项目路径**，可复制 |
| `last_assistant_message` | 不展示 | **正文主内容（完整）** |

**不截断**：`last_assistant_message` 上报与存储均为 **完整原文**；App 详情页滚动渲染。  
列表卡片仍只展示短字段 `message`，避免列表性能/布局问题。

---

## 监测端采集

### 完整路径 `cwd`

- **Claude**：Hook `cwd` **不要** `filepath.Base` 后再丢；上报时  
  - `Cwd` = 绝对路径原文  
  - `DisplayName` = `filepath.Base(cwd)`（兼容现有卡片）  
- **Codex**：已有 `s.cwd` 时同样：`Cwd` 全文，`DisplayName` = basename  

旧客户端忽略未知字段；旧服务端需 migrate 加列（见下）。

### Claude：最后 Agent 消息

1. 优先 Hook `transcript_path`  
2. 否则尝试 `~/.claude/projects/.../<sessionId>.jsonl`（若可拼出）  

`lastAssistantFromTranscript(path)`：

- 顺序扫 jsonl（或倒序读尾部窗口，实现阶段二选一，优先正确性）  
- `type == "assistant"` 或 `message.role == "assistant"`  
- 拼接 `content` 中 `type=text` 的 `text`  
- 取最后一条非空，**原样保留全文**（不做 runes 截断）  

触发：hook 写状态时；Stop / 周期 report 时若有 path 再刷一次。

### Codex：最后 Agent 消息

在现有 rollout 解析中：

- `response_item` / payload `type=message` + `role=assistant` → 抽 content 文本  
- 可选：`event_msg` + `agent_message` 正文（有则更新）  
- 内存态 `lastAssistant` 每次非空则覆盖  
- **不采** tool / function_call 输出正文  

---

## 存储 / API

- SQLite `sessions`：`ALTER` 增加  
  - `last_assistant_message TEXT`  
  - `cwd TEXT`  
- `ApplyReport` upsert 写入；`ListSessions` 读出  
- Memory store 同步  
- WS `session_upsert` payload 带上两字段  
- history 表**不**存最后消息全文  

---

## App 会话详情页 UI

### 路由

```text
/sessions/:machineId/:agent/:sessionId
```

- 首页 `TaskCard.onTap` → 会话详情（**不再**直接进设备页）  
- 设备页会话列表同样进详情  
- 详情内提供「查看设备」→ `/devices/:machineId`  

### 布局（自上而下）

```text
┌─────────────────────────────────────┐
│ ←  返回                              │  AppBar / 自绘顶栏
├─────────────────────────────────────┤
│  [需确认]  [Claude]                  │  状态色 chip + Agent chip
│  优化登录逻辑，修复偶现问题…          │  标题 = message（用户摘要）
│  设备 ThinkPad-X1 · 3 分钟前          │  machineName · 相对时间
│  路径                                │  小节标签
│  /home/ynlea/projects/agent-status   │  cwd 全文，可换行/可复制
├─────────────────────────────────────┤
│  Agent 最后消息                       │  区块标题
│  ┌─────────────────────────────┐    │
│  │ （可滚动正文）                 │    │
│  │ last_assistant_message        │    │
│  └─────────────────────────────┘    │
│  空：暂无 Agent 输出                  │
├─────────────────────────────────────┤
│  [复制最后消息]  [查看所属设备]       │  底部操作
│  更多（折叠）：session_id · source    │
└─────────────────────────────────────┘
```

### 头部信息清单（必有）

1. 返回  
2. 状态徽标 + Agent 徽标  
3. 标题：`message`，空则 `display_name`，再空则 `sessionId` 短展示  
4. 设备名 · 相对更新时间  
5. **完整项目路径 `cwd`**（标签「路径」+ 全文；无 cwd 时回退 `display_name`）  

### 正文

- 标题：「Agent 最后消息」  
- 内容：`last_assistant_message` **全文**，正文样式，多行可滚动（超长会话由列表滚动承载）  
- 空态文案：「暂无 Agent 输出」  

### 交互

- 长按路径 / 点「复制」→ 复制 cwd 或最后消息  
- 「查看所属设备」跳转设备详情  

### 风格

- 沿用青芽卡片圆角、状态色、Agent 色（与 `TaskCard` 一致）  
- 路径用次要文字色、可略小字号，保证长路径可读  

---

## 兼容与发版

- 旧监测端：无新字段 → 详情正文空态、路径回退 display_name  
- 旧 App：忽略新字段  
- 发版顺序建议：server（migrate）→ monitor → app  

## 风险

- transcript 很大：只保留**最后一条**全文（不整段历史）；扫描可后续优化尾部窗口  
- 单条 assistant 极长时：上报体变大、SQLite 行变大；可接受，详情靠滚动；若线上有瓶颈再加软上限  
- 隐私：全文上报最后一条；本版不做关闭开关  
- Claude 仅 basename 的旧数据：详情路径可能只有短名，升级 monitor 后恢复全文  
