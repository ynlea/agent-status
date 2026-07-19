# 轻芽原型素材第二版

## 风格基准

- 猫咪：贴近原型的柔和写实插画，真实毛发与自然比例，小尺寸仍能辨认品种和表情。
- 禁止：头顶叶片、夸张大眼、塑料玩具感、文字、贴纸白边和场景背景。
- 设备：简洁产品缩略图，正面或轻微三分之四视角，灰黑银配色。
- 导航：2px 圆角细线图标，空心结构，适合代码着色。
- 全部图板：严格 2×2、纯 `#00FF00` 绿幕、每象限一个主体。

## 使用边界

气泡轮廓、状态色、卡片背景和选中态继续由 Flutter 绘制，不进入位图素材。

## 交付结果

- 生成入口：`custom-imagegen` / `gpt-image-2`
- 图板：5 张严格 2×2 绿幕图板
- 图标：20 枚 512×512 透明 PNG
- 自动校验：四角透明、亮绿残留 0、文件名唯一、内容非空
- Flutter 副本：`flutter_assets/{cat,device,nav}/`

## 提示词骨架

```text
Create one square 2x2 mobile UI asset board on a perfectly flat uniform
vivid chroma-key green background exactly #00FF00.
Exactly four fully separated centered subjects, one per quadrant in reading order.
Style: soft premium semi-photorealistic prototype illustration for cats;
refined product thumbnail for devices; uniform rounded outline for navigation.
Keep generous green padding around every subject and across both center axes.
No text, numbers, watermark, border, separator, cast shadow, reflection,
white sticker outline, green subject details, or objects crossing quadrants.
```
