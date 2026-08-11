# PRD：修复用量首次回填与换服漏传

## 背景

监控端用量游标存在本机，与服务端身份无关。换新服务端或首次同步异常时，可能出现本地已标回填完成、服务端几乎无数据。

## 目标

1. 换服务端（server_url 变化）时自动全量重传用量。
2. 仅在上报成功路径上推进完成态；整次回填未成功时不标 backfill_done。
3. 服务端 dedupe 已存在，重传安全。

## 验收标准

- [x] 空游标首次同步成功后 backfill_done=true 且写入 server_url
- [x] server_url 变化后 offset 归零并重新上报
- [x] 上报失败时 backfill_done 不为 true
- [x] 现有 monitor 单测通过，并补换服/失败用例
