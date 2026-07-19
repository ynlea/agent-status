# Android App (Agent Status)

Kotlin + Jetpack Compose 客户端：配置私有服务、按机器查看多会话、本 App 系统通知。

## 构建

需要 Android SDK / JDK 17。在 `android/` 目录：

```bash
# 若无 wrapper，可用 Android Studio 打开本目录生成
./gradlew :app:assembleDebug
```

安装 debug APK 到手机后：

1. 填写 `http://<server>:8080` 与预共享密钥  
2. 允许通知权限  
3. 默认仅红灯（confirm）通知开启  

## 说明

本环境若未安装 Android SDK，无法在此机完成编译；源码与契约字段已对齐 `docs/api.md`。
