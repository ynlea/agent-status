# 轻芽卡通猫素材第三版

## 修正目标

- 依据 `source/原型图.png` 重画猫咪素材。
- 主视觉统一为奶油白与深棕重点色的卡通布偶猫。
- 列表猫保留白猫、灰虎斑、橘猫、布偶猫的识别差异，但统一为三维卡通插画。
- 禁止照片级毛发、真实宠物肖像、头顶叶片、文字、贴纸白边和场景背景。

## 交付结果

- 生成入口：`custom-imagegen` / `gpt-image-2`
- 图板：2 张严格 2×2 纯绿幕图板
- 图标：8 枚 512×512 透明 PNG
- 自动校验：四角透明、亮绿残留 0、文件名唯一、内容非空
- 额外处理：透明边缘去绿，并在暖米白界面底色上复核
- Flutter 副本：`flutter_assets/cat/`

## 分组

1. 首页布偶猫：挥爪眨眼、品牌头像、蜷睡空态、探头详情。
2. 列表状态猫：白猫、灰虎斑、橘猫、布偶猫。

## 提示词骨架

```text
Create one square 2x2 mobile UI asset board on a perfectly flat uniform
vivid chroma-key green background exactly #00FF00.
Exactly four fully separated centered subjects, one per quadrant in reading order.
Style: unmistakably cartoon, high-quality family animation film character,
simplified rounded volumes, softly sculpted fur masses, broad painted color shapes,
clean silhouette, expressive eyes, gentle matte shading, never photographic.
Keep generous green padding around every subject and across both center axes.
No text, watermark, border, separator, scenery, cast shadow, reflection,
white sticker outline, green subject details, or objects crossing quadrants.
```
