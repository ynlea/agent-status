# Design：用量游标绑定服务端

## 状态结构

`usageState` 增加：

- `ServerURL string`：上次成功绑定的服务端地址（规范化后）
- 保留 `BackfillDone`、`Files`、`LastDiscoverUnix`

## 规范化

比较前对 `server_url` 做 trim、去尾 `/`，避免无意义差异触发重扫。

## 启动 / SyncOnce 入口

1. `load()` 后若 `state.ServerURL != normalize(cfg.ServerURL)`：
   - 清空所有 file cursor（或全部 offset=0 且 drop size）
   - `BackfillDone=false`
   - `ServerURL=normalize(cfg.ServerURL)`（内存中先绑定目标；成功落盘时再确认）
2. 仅当本轮 `SyncOnce` 无上报错误结束时：
   - 可设 `BackfillDone=true`
   - `save()` 写出完整游标
3. 若 `ReportUsage` 失败：
   - **不**设 `BackfillDone=true`
   - 已成功上报并更新过 offset 的文件可 `save()` 中间进度（减少重传量）
   - 或更简单：失败直接 `return err` 且只在有成功推进时 save（不标 backfill）

选定：**失败时若 dirty（已有文件 offset 推进）则 save，但强制 `BackfillDone=false`；成功结束才允许 `BackfillDone=true`。**

## 兼容

旧游标无 `server_url` 字段：视为空，与当前 cfg 不一致 → 触发一次全量重传（可接受；dedupe 保底）。

## 测试

- 换 `ServerURL` 后 offset 归零且 backfill false
- 首次成功后 backfill true 且 server_url 写入
- 上报失败时 backfill 仍为 false
