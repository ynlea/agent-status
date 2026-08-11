# Implement

## Checklist

1. **real_usage**
   - [x] `FillDerived` 去掉 reasoning
   - [x] store 会话 real_usage 聚合去掉 reasoning
   - [x] 修正相关单测期望值

2. **Codex 回放去重**
   - [x] meta/签名/父索引/prefix 匹配
   - [x] ParseCodexUsageFile 支持跳过前缀并设 baseline
   - [x] UsageSyncer 接线
   - [x] 单测：父子 fixture

3. **验证**
   ```bash
   go test ./pkg/apitypes/ ./internal/monitor/ ./internal/store/ -count=1
   ```

4. **文档** 一句：真实用量口径；子会话去回放；需 rebuild-usage
