# 轻芽 UI 绿幕素材

> 第三轮猫咪视觉修正位于 `v3/`：2 张图板、8 枚透明 PNG，按原型重画为统一的三维卡通猫；设备缩略图和底栏图标继续使用 `v2/`。

## 交付物

| 路径 | 说明 |
|------|------|
| `boards-generated/` | 原始 2×2 绿幕图板（10 张） |
| `boards-normalized/` | 规范化 2048×2048 图板 |
| `icons/` | **主交付**：40 个 512×512 透明 PNG |
| `flutter_assets/` | 按类别分组的副本，便于迁入 Flutter `assets/images/` |
| `icon-groups.json` | 图板与文件名对照 |
| `icon-qa.json` | 自动校验报告（绿残留=0、四角透明） |

## 分类（flutter_assets）

- `cat/` 猫咪 IP 多姿态
- `agent/` Claude / Codex / 未知 / 通用
- `device/` 笔记本 / 台式 / 服务器 / 未知
- `nav/` 底栏与导航
- `settings/` 服务地址、密钥、主题、显隐
- `status/` 通知三态、连接态
- `action/` 刷新、展开折叠、警告
- `all/` 全量扁平副本

## Flutter 引用示例

```yaml
flutter:
  assets:
    - assets/images/cat/
    - assets/images/agent/
    - assets/images/device/
    - assets/images/nav/
    - assets/images/settings/
    - assets/images/status/
    - assets/images/action/
```

将 `flutter_assets/<类>/` 拷入工程 `assets/images/<类>/` 即可。

## 生成说明

- 接口：`custom-imagegen` / `gpt-image-2`
- 抠图：`create-ui-chroma-icons` extract 脚本
- 叶片等绿色为暖橄榄/棕绿，避免 `#00FF00` 误抠
