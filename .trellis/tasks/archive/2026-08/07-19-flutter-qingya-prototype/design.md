# Design: Flutter 轻芽按原型重做

## Overview

在仓库新建 Flutter 应用 `mobile/`，用 Material 3 + 自建 `QingyaTheme` 还原 `source/原型图.png`。数据层对齐现有 Agent Status API；UI 完全脱离 Kotlin Compose 单页结构。素材从 `source/ui-chroma/flutter_assets/` 拷入 `mobile/assets/images/`。

## Boundaries

| 层 | 职责 | 不负责 |
|----|------|--------|
| `mobile/lib/ui` | 页面、组件、主题、路由 | 摘要算法 |
| `mobile/lib/data` | REST/WS、本地配置、仓库 | 服务端存储 |
| `mobile/lib/domain` | 模型、状态枚举、排序规则 | 平台通道细节 |
| 监控 / server | 摘要与状态真相 | App UI |
| `source/ui-chroma` | 位图源 | 运行时加载路径（运行用 assets 副本） |

## 工程结构（建议）

```
mobile/
├── pubspec.yaml
├── assets/images/{cat,agent,device,nav,settings,status,action}/
├── lib/
│   ├── main.dart
│   ├── app.dart
│   ├── theme/qingya_theme.dart
│   ├── domain/{models,session_state}.dart
│   ├── data/
│   │   ├── api/{rest_client,ws_client,auth}.dart
│   │   ├── prefs/settings_store.dart
│   │   └── repo/status_repository.dart
│   ├── ui/
│   │   ├── shell/main_shell.dart          # 底栏
│   │   ├── home/home_page.dart
│   │   ├── devices/{devices_page,device_detail_page}.dart
│   │   ├── settings/settings_page.dart
│   │   ├── onboarding/welcome_page.dart
│   │   └── widgets/{task_card,device_tile,empty_state,agent_badge,status_dot}.dart
│   └── notify/local_notifier.dart
└── test/
```

## 视觉契约（贴原型）

从原型读取并固化到 Theme（实现时用取色/量间距微调）：

| Token | 方向值（初值，可微调） |
|-------|------------------------|
| `scaffoldBg` | 暖米白 `#FFF6F0` 向 |
| `cardBg` | `#FFFFFF` |
| `primary` | 暖橙珊瑚 `#F08A5D` 向 |
| `confirm` | `#E85D5D` 向 |
| `working` | `#F0A030` 向 |
| `done` | `#3CB371` 向 |
| `idle/offline` | 中性灰 |
| 卡片圆角 | 大圆角 ~20 |
| 底栏 | 白底；选中 primary + 填充 icon |
| 标题 | 深灰近黑，字重 semibold |

组件映射：

| 原型元素 | Flutter |
|----------|---------|
| 任务/会话卡 | `Card`/`Container` + 左色条或色点 + 双行 Text + `AgentBadge` |
| 设备行 | `ListTile` 定制：名 + `StatusDot` + chevron 图 |
| 底栏 | `NavigationBar` 自定义 destination + asset icon |
| 设置行 | 圆角分组容器 + Switch 主题色 |
| 空态/引导 | 插画 Image.asset + 文案 + 主按钮 |

**还原标准**：实现阶段每个主页面与原型对应屏截图并排；偏差只允许系统字体/安全区导致的微小差，不允许信息架构或主色跑偏。

## 导航

```
未配置 → WelcomePage →（保存配置）→ MainShell
MainShell
  ├── HomeTab
  ├── DevicesTab → DeviceDetail(machineId)
  └── SettingsTab
```

- 首页卡片点击 → `DeviceDetail`（可带 `sessionId` 高亮）
- 使用 `go_router` 或 `Navigator 2`；推荐 **`go_router`** 简明路由表

## 数据流

```
SettingsStore (URL, key, notify flags)
        │
        ▼
StatusRepository
  ├── RestClient GET /machines, GET /machines/{id}/sessions
  └── WsClient  notification / session_upsert
        │
        ▼
  Stream / Listenable  → UI (Riverpod 或 Provider；默认 Riverpod)
```

### 模型（对齐 API）

- `Machine`: id, name, platform, online, lastSeenAt  
- `Session`: machineId, agent, sessionId, displayName, state, message, updatedAt  
- 首页列表 = 全机 sessions 过滤 `state != idle`，排序 confirm > working > done，其次 updatedAt desc  

### 兼容

- `message` 可能是旧状态标签或新短摘要 → UI 原样展示；空则主标题回退 `displayName`  
- Agent 未知 → `agent_unknown.png`  

## 通知

- Android：`flutter_local_notifications` + 启动后权限请求  
- 通道可按状态分或单通道 + 标题区分  
- 开关：confirm / working / done 三个 bool；WS 入站时过滤  
- 文案：`title`=需确认|工作中|已完成；`body`=`{machine} · {agent} · {displayName} — {message}`  

## 依赖（初选）

| 包 | 用途 |
|----|------|
| `flutter` Material 3 | UI 基座 |
| `go_router` | 路由 |
| `flutter_riverpod` | 状态 |
| `dio` 或 `http` | REST |
| `web_socket_channel` | WS |
| `shared_preferences` | 配置 |
| `flutter_local_notifications` | 通知 |
| `equatable` / freezed（可选） | 模型 |

不默认引入大型第三方 UI Kit，避免与原型暖色冲突。

## 素材

- 构建前脚本或文档：从 `source/ui-chroma/flutter_assets/` 同步到 `mobile/assets/images/`  
- `pubspec.yaml` 声明各子目录  
- 缺口：实现 checklist 登记 → 走绿幕工作流补 4 图一组 → 再同步  

## 与旧 Android

- `android/` Kotlin 工程本任务不删、不验收  
- README 可注：客户端以 `mobile/` 为准  

## Trade-offs

| 选择 | 理由 | 代价 |
|------|------|------|
| 新建 Flutter 而非改 Compose | 你已定 Flutter + 原型重做 | 双端目录短期并存 |
| M3 自建 Theme | 贴原型可控 | 要比套件多写组件 |
| Riverpod | 列表+WS 刷新清晰 | 学习成本低 |
| 视觉硬对齐 | 满足「一模一样」 | 验收靠截图对比，耗时 |

## Rollback

- 删除或停用 `mobile/` 不影响 server/monitor  
- 配置仅在 App 本地，无服务端迁移  

## Test focus

- 排序与过滤单元测试  
- SettingsStore 读写  
- golden/截图测试（可选，主路径手动并排原型）  
- mock API 集成：首页/设备/详情/引导  
