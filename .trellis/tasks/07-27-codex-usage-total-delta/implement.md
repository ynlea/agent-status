# Implement: Codex total 差分

## Checklist

1. **解析核心**（`usage_parse.go`）
   - [x] 改 `ParseCodexUsageFile`：优先 total 差分；无 total 用 last；全 0 skip
   - [x] `cached = min(cached, rawIn)`
   - [x] 增加 `startTotal` 入参与 `lastTotal` 出参（类型可用 `map[string]int64` 或小结构体）
   - [x] `fromOffset > 0` 且无 startTotal 时 `recoverCodexTotalPrefix`
   - [x] 更新函数注释说明与 cc-switch 对齐点

2. **游标**（`usage_sync.go`）
   - [x] `fileCursor` 持久化 last total 四元组（或等价）
   - [x] 调用解析时传入/写回
   - [x] 文件截断 reset 时清空 total 基线

3. **测试**（`usage_parse_test.go`，必要时 sync 测）
   - [x] 改现有 `TestParseCodexUsageFile` 断言适配新签名；第二段仍按 total 差分（billed=100 等）
   - [x] **重复 last / total 不变** → 0 事件
   - [x] **三段 total 递增** → 两段或三段差分之和正确
   - [x] **仅 last 无 total** → 1 事件
   - [x] **中段 offset + 无 startTotal** → 前缀恢复后不把累计当 delta
   - [x] **中段 offset + startTotal** → 正确

4. **验证**
   ```bash
   go test ./internal/monitor/ -count=1
   ```

5. **文档（可选轻量）**
   - [x] 若 `docs/deploy.md` 有用量口径一句，补「Codex 按 total 差分；虚高历史可清游标重扫」

## Ready for start when

- prd / design / implement 已齐
- 无未决产品分歧（展示含 cache、子会话不归并已确认 out of scope）
