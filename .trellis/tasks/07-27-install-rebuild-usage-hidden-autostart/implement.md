# Implement

## Checklist

1. **Linux `install.sh`**
   - [x] `rebuild-usage` 命令与 `--confirm-rebuild-usage`
   - [x] 解析 DB / 游标路径；二次确认；sqlite3 删 `usage_events`；删游标；restart monitor
   - [x] usage / 菜单项

2. **Windows `install.ps1`**
   - [x] 同上（`-ConfirmRebuildUsage`）
   - [x] 抽取无窗启动；`Enable-Role` 注册隐藏启动任务；覆盖旧任务
   - [x] 菜单项

3. **文档**
   - [x] `docs/install.md`：rebuild-usage、Windows 自启说明、sqlite3 依赖

4. **自检**
   - [x] bash -n install.sh
   - [x] 人工过一遍 ps1 语法（无 Windows 则静态审查 Enable-Role / rebuild）

## Ready for start when

规划已审阅。
