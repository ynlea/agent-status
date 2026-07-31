# Pi 平台用 pi-subagents 派发 trellis sub-agent

本文档说明 Pi 平台如何通过 pi-subagents 的 `Agent` 工具派发 `trellis-implement` / `trellis-check` / `trellis-research` 子代理，用于验证 trellis 工作流改用 Agent 工具后的 implement→check 派发链路。

## 前置条件

1. **安装 pi-subagents**（Pi 的 Agent/子代理插件）：

   ```bash
   pi install npm:@tintinweb/pi-subagents
   ```

   安装完成后重启 Pi，使插件与 agent 定义生效。

2. **Trellis 已初始化**：仓库内 `.trellis/` 已就绪，且能解析当前活动任务：

   ```bash
   python3 ./.trellis/scripts/task.py current --source
   ```

   应输出 `Current task: <task path>`。子代理依赖此命令作为"无 `Active task:` 前缀时的兜底任务解析"。

3. **agent 定义已就位**：`.pi/agents/trellis-implement.md`、`trellis-check.md`、`trellis-research.md` 三个文件存在（详见下文"agent 定义"）。

## 派发方式

主会话通过 pi-subagents 的 **`Agent` 工具**派发子代理（工作流已弃用 `trellis_subagent` 工具，仅保留注册为回退），关键点：

- `subagent_type` 取 `trellis-implement` / `trellis-check` / `trellis-research` 之一；
- **prompt 必须以 `Active task: <task path>` 开头**（第一行），子代理据此加载任务上下文；无此前缀时才回退到 `task.py current --source`。

### 用法示例

以下伪代码示意 Pi 会话中派发子代理的调用形态（字段名以 Pi 会话的实际 Agent 工具为准）：

```text
Agent tool call:
  subagent_type: "trellis-implement"   # 或 "trellis-check" / "trellis-research"
  prompt: |
    Active task: .trellis/tasks/07-31-07-31-trellis-pi-subagents-test
    （后续为角色指令，如"按 prd.md 实现 / 校验改动 / 调研并落盘 findings"）
```

对应到 workflow.md 的 `[Pi]` 平台块：

```text
- in_progress 实现/校验 -> 通过 Agent 工具（pi-subagents）以
  subagent_type: "trellis-implement" / "trellis-check" 派发；不要用 trellis_subagent。
- 派发 prompt 以 `Active task: <task path from task.py current>` 开头。
```

### 子代理类型一览

| subagent_type | 职责 | 说明 |
|---------------|------|------|
| `trellis-implement` | 实现 | 读 spec/prd 后落地代码/文档，禁止 git commit |
| `trellis-check` | 质量校验 | 对照 spec 复核改动、直接修复问题、跑质量门禁 |
| `trellis-research` | 调研 | 定位相关文件/模式并落盘到任务 research/ 目录 |

## Agent 定义

三个子代理类型定义在仓库根目录 `.pi/agents/` 下，Pi 启动时读取：

| 文件 | 定义的类型 |
|------|-----------|
| `.pi/agents/trellis-implement.md` | `trellis-implement` |
| `.pi/agents/trellis-check.md` | `trellis-check` |
| `.pi/agents/trellis-research.md` | `trellis-research` |

### frontmatter 约定

- `name`：与 `subagent_type` 一致；
- `description`：子代理角色说明；
- `tools`：**必须使用 Pi 内置的小写工具名**（`read, write, edit, bash, grep, find, ls`），不得使用平台专属大写工具名。

示例（`trellis-implement.md`）：

```markdown
---
name: trellis-implement
description: |
  Code implementation expert. Understands Trellis specs and requirements, then implements features. No git commit allowed.
tools: read, write, edit, bash, grep, find, ls
---
```

> `trellis-research.md` 未声明 `edit` 工具（只读调研），即 `tools: read, write, bash, grep, find, ls`。

## 验证方式

1. **重启 Pi**（使 `.pi/agents/` 定义与 pi-subagents 插件加载生效）；
2. 打开 **`/agents` 面板**，应列出 3 个 trellis agent 类型：`trellis-implement`、`trellis-check`、`trellis-research`；
3. 在主会话中用 `Agent` 工具派发一次 `trellis-implement`（prompt 首行带 `Active task:` 前缀），确认子代理能加载任务上下文并返回结果，即验证 implement→check 派发链路打通。

## 平台隔离说明

**此改造只影响 Pi 平台。**

- Pi 平台改用 pi-subagents 的 `Agent` 工具派发子代理，并依赖 `.pi/agents/` 下的 agent 定义；
- **Codex / Claude Code** 等其他平台继续使用各自原有的派发机制（如 Task 工具 / subagent CLI / Skill），trellis 工作流不受影响。

如需确认：查看 `.trellis/workflow.md` 中各平台块（`[Claude Code, ...]`、`[Pi]`、`[codex-inline, ...]`）——只有 `[Pi]` 块写的是"通过 Agent 工具（pi-subagents）派发"。
