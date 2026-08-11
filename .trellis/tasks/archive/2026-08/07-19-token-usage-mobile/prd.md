# Token 用量：Flutter 用量页

## Goal

在轻芽 App 增加用量页，按设备/渠道/时间查看汇总与模型细分，展示真实用量、输入输出、缓存命中率与估算费用。

## Parent

`07-19-multi-device-token-usage` — UI 指标与筛选以父任务 `prd.md` / `design.md` 为准。

## Dependencies

**依赖** `07-19-token-usage-server` 查询 API。  
监控端有数据后体验更完整，但可用 mock/fixture 先联调。

## Requirements

- 路由 `/usage` + 主导航入口
- 快捷：当天、1 天、7 天、30 天、自定义（客户端换算 from/to）
- 筛选：设备、渠道；breakdown：模型/渠道
- Hero：真实用量、估算费用、命中率等
- 输出默认含 reasoning；明细可展开
- 标注「估算非账单」；下拉刷新

## Acceptance Criteria

- [x] 能完成筛选并展示 summary + breakdown
- [x] 无数据/失败有明确空态
- [x] 不影响首页会话状态流
- [x] `flutter analyze` 通过

## Status

实现完成（2026-07-19）：底部「用量」Tab、时间/设备/渠道筛选、Hero 汇总、按模型/渠道/设备明细与 reasoning 展开。
