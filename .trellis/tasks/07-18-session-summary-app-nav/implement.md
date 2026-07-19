# Implement: 会话摘要与 App 导航重设计

## Order

按序执行；前一步测试通过再进后一步。

### 1. 共享摘要工具

- [x] 在 `internal/monitor` 增加 `ShortSummary(text string, maxRunes int) string`（默认 48）
- [x] 单测：空串、多行只取首行、超长截断带 `…`、空白压缩

### 2. Claude hook 摘要 + 保留策略

- [x] `HookEvent` 增加 `UserPrompt string \`json:"user_prompt"\``
- [x] `ApplyHookEvent`：合并已有 session；UserPromptSubmit 写摘要；Stop/工具类保留摘要
- [x] 更新/补充 `internal/monitor` 相关测试（含 Stop 不擦除摘要）
- [x] 确认日志只打短 message，不打 raw prompt

### 3. Codex 摘要 + 保留策略

- [x] rollout `user_message` 提取正文 → `ShortSummary`
- [x] 后续事件避免用事件名覆盖已有摘要（confirm 无摘要时可用标签）
- [x] app-server 路径对齐（若有用户文本）
- [x] 单测覆盖正文提取与保留

### 4. 文档语义

- [x] `docs/api.md` / `docs/deploy.md`：说明 `message` 优先为短摘要，仍禁止全文

### 5. Android 主题与导航骨架

- [x] Theme：跟随系统 light/dark（Material3）
- [x] 引入 navigation-compose（若缺失） → 本版用底栏状态切换，无需额外依赖
- [x] 底栏：首页 / 设备 / 设置
- [x] 首次未配置：引导进设置或阻塞式配置页

### 6. Android 页面

- [x] **首页**：聚合所有机器非 idle 会话；排序 confirm > working > done；卡片主副标题
- [x] **设备页**：机器列表 + 在线状态
- [x] **设备详情**：该机会话；活跃上、idle 折叠
- [x] **设置**：URL、密钥、通知红黄绿；保存后回到可用状态
- [x] 从首页点击跳转设备详情

### 7. 通知与列表文案

- [x] `Notifier` 使用目录 + 摘要格式
- [x] 列表无摘要时降级只显示目录/agent

### 8. 验证

- [x] `go test ./...`
- [x] Android：`./gradlew :app:assembleRelease` → `dist/agent-status-0.1.0-release.apk`
- [x] 会话摘要：Claude/Codex 截断 + Stop 保留；完成态文案为「完成」非「停止」
- [x] App 导航：首页 / 设备 / 设置 + 设备详情；BackHandler 返回
- [x] 后台：`:monitor` 独立进程 + FGS + 配置文件同步 + 开机拉起
- [ ] 手动：装新包后确认常驻通知 `● WebSocket 已连接`，回桌面后通知仍在且状态变化仍能收到
- [ ] 手动：完成一轮 Claude 任务，摘要 + 「完成」chip/通知正确

## Validation commands

```bash
go test ./...
go build -o bin/agent-status-monitor ./cmd/monitor
go build -o bin/agent-status-server ./cmd/server

# optional
cd android && ./gradlew :app:assembleDebug
```

## Risky files

| 文件 | 风险 |
|------|------|
| `internal/monitor/claude.go` | 状态机回归；摘要被覆盖 |
| `internal/monitor/codex.go` / appserver | 误把工具输出当用户摘要 |
| `android/.../MainActivity.kt` | 大改导航，易漏配置入口 |
| 日志路径 | 意外打印完整 prompt |

## Rollback points

1. 仅合并监控摘要，App 未改 → 可单独用
2. App 导航不稳 → 回退 Android，监控摘要仍可用
3. 摘要质量差 → 调 `maxRunes` 或仅首行策略，无需迁库

## Before `task.py start`

- [x] `prd.md` 决策闭合
- [x] `design.md` 写完
- [x] `implement.md` 写完
- [ ] 用户审阅通过
