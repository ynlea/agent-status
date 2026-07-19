# 轻芽（Qingya）Flutter 客户端

按 `source/原型图.png` 重做的只读监控 App：首页活跃任务 / 设备 / 设置。

## 运行

```bash
export PATH="$HOME/flutter/bin:$PATH"
cd mobile
flutter pub get
flutter run
```

首次进入可点 **「先用演示数据看看」** 预览 UI；或 **开始配置** 填写服务地址与密钥。

接 mock：

```bash
# 仓库根目录
go run ./cmd/mock -addr :8080 -key dev-secret
# App 设置：http://<主机IP>:8080  +  dev-secret
```

## 素材

来自 `source/ui-chroma/flutter_assets/`，已拷入 `assets/images/`。

## 结构

- `lib/theme` — 暖色 Theme
- `lib/ui` — 页面与组件
- `lib/data` — REST / WS / 本地配置
