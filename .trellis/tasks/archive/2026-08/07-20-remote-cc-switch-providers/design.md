# Design: 远程管理 cc-switch 供应商

## 1. Architecture

```
App (Flutter)
  │ REST: list snapshot / enqueue cmd / poll cmd status
  ▼
Server (Go + SQLite)
  │ store: provider snapshots, command queue
  │ auth: existing pre-shared key
  ▲
Monitor (Go)
  │ every ~5s: pull pending cmds for machine_id
  │ on change / ~60s: push provider snapshot (+ existing session report)
  ▼
Local cc-switch
  - read/patch ~/.cc-switch/cc-switch.db
  - exec: cc-switch use <id> -a codex|claude
```

**Boundary**

| 层 | 职责 |
|----|------|
| App | 展示列表、发起 switch/update、展示命令状态；不直连用户机器 |
| Server | 鉴权、按 machine 存快照、命令队列与超时、查询 API |
| Monitor | 唯一写本机 cc-switch 的执行者；脱敏上报；执行命令并回报 |
| cc-switch | 真相源；CLI 负责 apply live |

**非目标**：监控端不实现完整 cc-switch UI 语义复制；只做约定字段 patch + switch。

## 2. Data model (server)

### 2.1 Provider snapshot（按机器缓存）

表建议 `provider_snapshots`（或 JSON blob 挂在 machine 旁表）：

- `machine_id`, `app` (`codex`|`claude`)
- `payload_json`：见 §3 snapshot DTO
- `updated_at`

每次 monitor 上报整表替换该 `(machine_id, app)` 快照（简单、一致）。

### 2.2 Commands

表 `machine_commands`：

| 列 | 说明 |
|----|------|
| `id` | uuid |
| `machine_id` | 目标机 |
| `app` | codex\|claude |
| `type` | `switch_provider` \| `update_provider` |
| `payload_json` | 类型相关参数（含可选 api_key，**应用层访问后日志脱敏**） |
| `status` | `queued` \| `running` \| `succeeded` \| `failed` \| `timed_out` \| `cancelled` |
| `error_message` | 短文本，无密钥 |
| `created_at` / `started_at` / `finished_at` |
| `lease_until` | 防重复领取 |

规则：

- 同一 `machine_id` **串行**：同时最多一个 `running`；`queued` FIFO。
- 超时：`queued` 超过 T1（如 120s）或 `running` 超过 T2（如 60s）→ `timed_out`。
- 机器离线判定：沿用现有 `last_seen_at`；App 下发时可告警，仍允许入队，由超时收口。

**密钥存储**：`update_provider` 的 `api_key` 若入队，仅存于命令行 payload，成功/失败后可清空 payload 中的 key 字段（或整行归档时剥离）。默认不写独立 secrets 表。

## 3. Contracts (API)

均需现有 Bearer key。路径前缀 `/api/v1`。

### 3.1 Monitor → Server：上报快照

`POST /api/v1/providers/report`

```json
{
  "machine_id": "m1",
  "machine_name": "desk",
  "platform": "linux",
  "reported_at": "...",
  "apps": [
    {
      "app": "codex",
      "current_id": "…",
      "providers": [
        {
          "id": "…",
          "name": "anyrouter",
          "base_url": "https://…",
          "model": "gpt-5.6-sol",
          "category": "custom",
          "has_api_key": true
        }
      ]
    },
    {
      "app": "claude",
      "current_id": "…",
      "providers": [
        {
          "id": "…",
          "name": "…",
          "base_url": "http://…",
          "model_alias": "sonnet",
          "anthropic_model": "grok-4.5[1m]",
          "default_haiku_model": "…",
          "default_sonnet_model": "…",
          "default_opus_model": "…",
          "has_api_key": true
        }
      ]
    }
  ]
}
```

**禁止**出现明文 key。

### 3.2 Monitor → Server：拉命令

`POST /api/v1/commands/pull`

```json
{ "machine_id": "m1", "limit": 1 }
```

响应：

```json
{
  "commands": [
    {
      "id": "cmd-…",
      "app": "codex",
      "type": "switch_provider",
      "payload": { "provider_id": "…" }
    }
  ]
}
```

领取即标记 `running` + `lease_until`。limit 默认 1 保证串行。

### 3.3 Monitor → Server：命令结果

`POST /api/v1/commands/{id}/result`

```json
{
  "machine_id": "m1",
  "status": "succeeded",
  "error_message": "",
  "providers_report": { /* 可选：成功后附带最新 apps 快照，省一次往返 */ }
}
```

### 3.4 App → Server：读快照

`GET /api/v1/machines/{id}/providers?app=codex|claude|all`

### 3.5 App → Server：下发命令

`POST /api/v1/machines/{id}/commands`

```json
{
  "app": "claude",
  "type": "update_provider",
  "payload": {
    "provider_id": "…",
    "name": "optional",
    "base_url": "optional",
    "api_key": "optional-only-if-changed",
    "model_alias": "optional",
    "anthropic_model": "optional",
    "default_haiku_model": "optional",
    "default_sonnet_model": "optional",
    "default_opus_model": "optional",
    "model": "optional-codex"
  }
}
```

`switch_provider` payload：`{ "provider_id": "…" }`。

响应：`{ "command_id", "status": "queued" }`。

`GET /api/v1/commands/{id}` 查状态。

可选：WS 事件 `command_updated` / `providers_updated`（MVP 可用 REST 轮询，间隔 1–2s，直到终态）。

## 4. Monitor: cc-switch adapter

### 4.1 路径

- DB：`~/.cc-switch/cc-switch.db`（可用 env/配置覆盖）
- CLI：`PATH` 中 `cc-switch`（配置可指定绝对路径）

### 4.2 Read（列表）

`SELECT id, name, website_url, category, is_current, settings_config FROM providers WHERE app_type=?`

映射：

**codex**

- `api_key` ← `settings.auth.OPENAI_API_KEY`（仅 `has_api_key`）
- `base_url` / `model` ← 解析 `settings.config` TOML 字符串中的 `base_url`、`model`（正则或轻量解析即可；不引入重型 TOML 写依赖时，写路径用「行级替换」）

**claude**

- `api_key` ← `env.ANTHROPIC_AUTH_TOKEN`
- `base_url` ← `env.ANTHROPIC_BASE_URL`
- `model_alias` ← 顶层 `model`
- `anthropic_model` ← `env.ANTHROPIC_MODEL`
- `default_*` ← 对应 DEFAULT 环境键

### 4.3 Update（patch）

1. 读出该行 `settings_config` JSON。
2. 按 payload 中**出现的字段**修改：
   - codex：改 `name` 列；改 auth key；在 config 文本中替换/插入 `model`、`base_url` 行（保留其它 TOML）。
   - claude：改 `name` 列；改 `env` 与顶层 `model`；**深合并**，保留 hooks/permissions/其它 env。
3. `UPDATE providers SET name=?, settings_config=? WHERE id=? AND app_type=?`。
4. 若 `is_current` 或 id==current：执行 `cc-switch use <id> -a <app>`。

### 4.4 Switch

`cc-switch use <provider_id> -a <app>`；检查 exit code + 可选再读 `is_current`。

### 4.5 并发

- 本机命令执行互斥锁（进程内 mutex）。
- SQLite 短事务；失败回滚内存变更不写半截（UPDATE 原子）。

### 4.6 配置扩展（monitor.json）

```json
{
  "cc_switch_db": "",
  "cc_switch_bin": "cc-switch",
  "command_poll_sec": 5,
  "provider_report_sec": 60
}
```

缺省值：poll 5s；provider 快照可与 session report 同触发，并在命令成功后立即推一次。

## 5. App UX（要点）

- **入口（已拍板）**：设备详情页（`/devices/:machineId`）机器头下方增加「供应商 / cc-switch」入口行/卡片，进入子路由 `/devices/:machineId/providers`；页内 Tab：Codex | Claude。不放设置、不加底栏 Tab。
- 列表：名称、当前角标、model 摘要、base_url 截断。
- 操作：设为当前；编辑表单（按 app 显隐字段）；api_key 占位「已配置 / 留空不改」。
- 下发后按钮 loading，轮询 command 至终态；失败 Snackbar 显示 `error_message`。
- 文案提示：不保证运行中会话立即切换。

> 注：仓库 frontend spec 仍写「只读」；本功能是**有意扩展**的控制面，范围仅限供应商管理，不做会话 approve。

## 6. Compatibility & rollout

- 旧 monitor：不拉命令、不上报 providers → App 显示「监控端未支持 / 暂无数据」。
- 服务端新表 migration 随 server 启动。
- 无需改 cc-switch 本身。

## 7. Security

- 全站仍共享一个 key（与现状一致）；命令能力随 key 生效——文档提示 key 泄露风险升高。
- 日志：禁止打印 payload.api_key / ANTHROPIC_AUTH_TOKEN / OPENAI_API_KEY。
- 响应给 App 的快照永不含 key；仅 `has_api_key`。

## 8. Trade-offs

| 选择 | 原因 | 代价 |
|------|------|------|
| 拉命令而非 WS 下行 | 贴合现有 monitor 模型 | 数秒延迟 |
| 直写 DB + CLI switch | add/edit 无稳定非交互 API | 需跟 cc-switch schema 演进 |
| 单任务交付 | 用户选择 | 分支大、需严格检查清单 |
| 命令内短暂存 key | 实现简单 | 须结果后剥离与日志规范 |

## 9. Rollback

- 功能开关：monitor 不配置 poll 即不执行命令；server 可保留表但不暴露 App 入口（或 App 隐藏入口）。
- 误编辑：cc-switch 本机仍有备份目录 `~/.cc-switch/backups`（不自动调用，运维可恢复）。
