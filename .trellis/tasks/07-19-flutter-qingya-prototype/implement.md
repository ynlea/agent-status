# Implement: Flutter 轻芽按原型重做

## Checklist

### 0. 开工前

- [ ] 你确认 Open questions（目录 `mobile/`、M3 Theme、Android 优先、旧 android 暂留）
- [ ] `task.py start` 本任务
- [ ] 本机 `flutter doctor` 可用

### 1. 工程脚手架

- [x] `flutter create mobile --org com.qingya --project-name qingya`
- [x] 配置 `pubspec` 依赖：go_router、riverpod、http、web_socket_channel、shared_preferences（通知包已引入待接线）
- [x] 同步素材到 `mobile/assets/images/*`
- [x] assets 声明完成

### 2. 主题与原子组件

- [x] `QingyaTheme` 浅色 + 深色保底
- [x] `StatusDot` / 色条、`TaskCard`、设备行、`EmptyState`、主按钮
- [x] 与原型并排微调 token（固定 390×844 截图完成一轮视觉 polish）

### 3. 数据层

- [x] 模型 + state 排序工具
- [x] `SettingsStore`
- [x] `RestClient`
- [x] `WsClient` + 重连
- [x] `StatusRepository` + 演示数据

### 4. 路由与壳

- [x] 未配置 → Welcome；已配置 → MainShell
- [x] 底栏三 Tab + 素材 icon
- [x] DeviceDetail 路由

### 5. 页面还原（按屏）

- [x] Welcome / Setup
- [x] Home + 空态
- [x] Devices + 空态
- [x] DeviceDetail（活跃 / idle 折叠）
- [x] Settings（地址/密钥/三开关/主题）
- [x] 连接态 / 错误提示

### 6. 通知

- [ ] 权限与渠道（下一轮）
- [ ] WS → 本地通知；三开关过滤
- [ ] 文案格式对齐 PRD

### 7. 联调与视觉验收

- [x] 演示数据驱动首页 / 设备 / 详情 / 设置主路径
- [x] 首页、设备、详情、设置、引导固定尺寸截图已生成
- [ ] 系统通知与首页空态单独截图验收
- [x] 用户复核后补绘第二版：5 张绿幕图板、20 枚透明 PNG，并替换首页猫、列表猫、设备图和底栏图标

### 8. 收尾

- [x] README 增加 `mobile/`
- [x] `flutter analyze` 无 issue；3 项测试通过；debug APK 构建通过
- [ ] 真机视觉验收通过后勾 AC

## 验证命令

```bash
cd mobile && flutter pub get
flutter analyze
flutter test
flutter run   # 指定设备
```

Mock 服务（仓库已有则）：

```bash
# 按 docs 启动 mock / server，App 填入 base URL + key
```

## 素材补绘触发

实现中若出现：

- 原型有、assets 无
- 或现图标小尺寸不可辨

则：

1. 记入 `source/ui-chroma/GAPS.md`（语义、尺寸、所在屏）
2. 绿幕 2×2 补组 → 抠图 → 同步 `assets/images`
3. 不在业务代码里长期 `Icons.help` 充数（临时除外并标 TODO）

## 回滚点

| 点 | 动作 |
|----|------|
| 脚手架失败 | 删 `mobile/` 重来 |
| 主题跑偏 | 只回滚 `theme/` + widgets |
| 数据层不稳 | UI 先接假数据 Provider |
| 整包放弃 | 不发布 `mobile/`，旧 android 仍在 |

## 风险

- 原型间距需真机微调，预留视觉 polish 一轮
- 后台 WS/通知受厂商杀后台影响，先保证前台与标准通知路径
- 深色模式原型未给：以浅色验收为准，深色保底可读
