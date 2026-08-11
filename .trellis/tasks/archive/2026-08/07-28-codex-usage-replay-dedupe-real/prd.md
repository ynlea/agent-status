# Codex 用量对齐 cc-switch：子会话回放去重与真实用量口径

## Goal

把 Codex 用量统计进一步对齐 cc-switch：子会话跳过从父会话回放的 token 前缀；「真实用量」与 cc-switch「真实消耗」同一套加总（fresh + output + cache，reasoning 不计入 real 体积）。

## Confirmed facts

- 双方 Codex 均用 total 差分；我们 input 已是 billed/fresh。
- `FillDerived` 当前把 reasoning 折进 out 再计入 real；cc-switch real 无 reasoning 分项。
- cc-switch 对 subagent 跳过与父文件匹配的 token 回放前缀；我们整文件计入导致父上下文重复。

## Product decisions

| 项 | 结论 |
|----|------|
| 子会话 | 跳过回放前缀后再计增量 |
| real_usage | in + output + cache（不含 reasoning） |
| 父缺失 | 整文件仍计，打日志 |
| 历史 | rebuild-usage 重扫 |

## Requirements

1. 子会话回放前缀不产生 UsageEvent，但推进 total 基线。
2. real_usage 公式对齐；会话列表聚合一致。
3. 单测覆盖。

## Acceptance Criteria

- [x] 父子回放前缀不计入子用量
- [x] root 行为不回退
- [x] real 不含 reasoning
- [x] 测试通过

## Out of scope

- 自动洗历史库；改「真实用量」文案。
