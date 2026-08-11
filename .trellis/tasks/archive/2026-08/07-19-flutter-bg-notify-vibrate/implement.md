# Implement: Flutter 后台监测与通知震动

## Checklist

1. **Android 宿主权限与组件**
   - 更新 `mobile/android/app/src/main/AndroidManifest.xml`：权限、`StatusMonitorService`、`BootReceiver`
   - 确认 `minSdk` / `targetSdk` 与 `foregroundServiceType=dataSync` 兼容

2. **移植原生监测栈**（参考 `android/app/src/main/java/com/agentstatus/app/`）
   - `MonitorConfigStore`
   - `WsClient` + 事件类型
   - `Notifier`（告警音+振 + ongoing 静音）
   - `StatusMonitorService`（`:monitor`、`START_STICKY`、`onTaskRemoved`）
   - `BootReceiver`
   - 包名改为 `com.qingya.qingya…`；字符串资源进 `res/values/strings.xml`

3. **MethodChannel 桥**
   - 在 `MainActivity` 注册 `qingya/monitor`
   - 方法：`syncAndStart`、`stop`、（可选）`ensureChannels`
   - Flutter 封装 `MonitorBridge`（`mobile/lib/data/…`）

4. **Flutter 配置接线**
   - `SettingsStore.save` / 开关变更后：非 demo 且已配置 → `syncAndStart`；否则 `stop`
   - App 启动已配置时自动 `syncAndStart`
   - Android 13+ 请求通知权限后再启动服务
   - 演示模式强制 `stop`

5. **防重复与 UI**
   - 确认 `StatusRepository` 不弹本地通知
   - 设置页补一句后台/通知说明（简短）

6. **验证**
   - 见下方 Validation
   - 有设备则装 debug/release 包实测后台

7. **文档（可选）**
   - `mobile/README.md` 补后台权限与验收要点

## Validation

```bash
# 静态
cd mobile && flutter analyze
# 有设备时
flutter run
# 或打 release
flutter build apk --release
```

真机场景：

1. 配置真实 server + key → 出现 ongoing「已连接/连接中」
2. 退后台，触发 monitor 上报 confirm → 通知+音+振
3. 关「需确认」开关 → 再触发 confirm 不响
4. 划掉最近任务 → 观察 ongoing 是否回来
5. 重启手机 → ongoing 自动出现
6. 演示模式 → 无真实监测服务

## Risky files / rollback points

| 文件 | 风险 |
|------|------|
| `mobile/android/.../AndroidManifest.xml` | 权限/Service 配错导致安装或 FGS 崩溃 |
| `StatusMonitorService` | 前台服务 5s 内未 startForeground 会 ANR/崩溃 |
| `SettingsStore` + bridge | 双写失败导致后台读到旧配置 |
| Channel ID | 改默认后用户端仍用旧渠道行为 → 需 bump |

回滚：移除 Service 注册与 bridge 调用即可回到前台-only。

## Before `task.py start`

- [x] `prd.md` 产品决策闭合
- [x] `design.md` 技术方案
- [x] `implement.md` 执行清单
- [x] 用户确认可开工

## Implementation status

- [x] Android 权限 / Service / BootReceiver
- [x] 移植 monitor 栈（config / ws / notifier / service / boot）
- [x] MethodChannel `qingya/monitor`
- [x] Flutter SettingsStore 同步
- [x] 设置页说明
- [x] `flutter analyze` 通过
- [x] `flutter build apk --debug` 通过
- [ ] 真机后台/震动验收（需用户设备）
