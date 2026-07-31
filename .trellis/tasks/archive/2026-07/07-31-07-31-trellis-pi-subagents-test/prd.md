# docs: Pi 平台用 pi-subagents 派发 trellis sub-agent 说明

## Goal

轻量文档任务:在 docs/ 下新建说明文档,记录 Pi 平台如何用 pi-subagents 的 Agent 工具派发 trellis-implement/trellis-check/trellis-research(本次 trellis 工作流改造的说明)。用于验证 trellis 工作流改用 Agent 工具后 implement→check 派发链路。

## Requirements

- 在 `docs/` 下新建文档 `docs/pi-subagents-trellis-integration.md`
- 内容:记录 Pi 平台如何用 pi-subagents 的 `Agent` 工具派发 `trellis-implement` / `trellis-check` / `trellis-research`
- 文档需包含:前置条件(安装 pi-subagents)、派发方式(subagent_type 用法、Active task 前缀)、验证方式(/agents 面板、重启 pi)
- 明确说明:此改造只影响 Pi 平台,Codex / Claude Code 等其他平台工作流不受影响

## Acceptance Criteria

- [ ] `docs/pi-subagents-trellis-integration.md` 存在且内容完整
- [ ] 文档包含 Agent 工具派发 trellis-* 的具体用法示例
- [ ] 文档包含平台隔离说明(只影响 Pi)

## Notes

- Keep `prd.md` focused on requirements, constraints, and acceptance criteria.
- Lightweight tasks can remain PRD-only.
- For complex tasks, add `design.md` for technical design and `implement.md` for execution planning before `task.py start`.
