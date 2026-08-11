# Implement

1. 改 `internal/monitor/usage_sync.go`：状态字段、normalize、换服重置、失败不标完成、成功写 ServerURL
2. 改/补 `internal/monitor/usage_sync_test.go`
3. `go test ./internal/monitor/ -count=1`
4. 本地如有需要：清游标或改配置验证（可选）
