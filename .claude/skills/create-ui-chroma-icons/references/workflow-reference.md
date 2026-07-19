# 调研、分组与绘制参考

## 调研表

先沿真实实现核对页面，不只读视觉截图。

| 页面区域 | 真实字段或动作 | 当前表现 | 现有素材 | 处理 | 新图标语义 |
| --- | --- | --- | --- | --- | --- |
| 摘要区 | `flowLevel` | 文字与档位 | 无 | 新绘制 | 流量刻度水滴 |
| 记录弹层 | `flowLevel` | 五档按钮 | 无 | 复用摘要图标 | 流量刻度水滴 |

检索顺序：

1. 页面模板中的标题、字段标签、按钮、状态和图例；
2. 页面脚本中的选项数组、枚举映射与条件分支；
3. 类型、服务和后端契约中的真实字段；
4. 当前图标组件、图标常量和素材目录；
5. 目标尺寸、背景色、禁用态和空态。

## 分组规则

- 先按用户高频路径分组，再处理日历状态、趋势、提醒和装饰。
- 让同一张图板内的四个图标复杂度接近，避免一个巨大主体挤压其它象限。
- 把需要复用的字段图标放在首批，不重复绘制枚举档位。
- 每个图标只表达一个稳定语义；不要把标题文字画进图标。

本项目 health-cycle（健康周期）页面的参考分组：

| 分组 | 左上 | 右上 | 左下 | 右下 |
| --- | --- | --- | --- | --- |
| 记录状态 | 流量刻度水滴 | 经血颜色色卡 | 痛经热水袋 | 备注手帐本 |
| 更多记录 A | 心情樱花脸 | 症状身体轮廓 | 复古体重秤 | 基础体温计 |
| 更多记录 B | 分泌物水滴 | 同房双爱心 | 记录状态剪贴板 | 更多记录收纳盒 |
| 周期阶段 | 月经期红色水滴 | 预测经期虚线水滴 | 排卵期花苞 | 排卵日珍珠星光 |
| 日期状态 | 今天樱花书签 | 已记录勾选印章 | 未记录空白便签 | 周期完成花环 |
| 趋势摘要 | 平均周期循环日历 | 平均经期水滴日历 | 近 30 天手帐页 | 痛经趋势热水袋 |
| 设置提醒 | 时区地球时钟 | 智能预测星光日历 | 经期提醒水滴铃铛 | 每日记录笔记铃铛 |

## 绿幕图板提示词骨架

```text
Create one square 2x2 icon board on a perfectly flat vivid chroma-key green background (#00FF00).
Exactly four fully separated centered objects, one per quadrant, in reading order: top-left <A>; top-right <B>; bottom-left <C>; bottom-right <D>.
Keep generous empty green padding around every object and across both center axes.
Style: <从已有素材提取的风格、配色、材质、描边与小尺寸要求>.
Do not use #00FF00 or similar bright green in any subject; render leaves in warm olive or brown-green.
No text, letters, numbers, watermark, border, frame, separator line, cast shadow, reflection, or white sticker outline.
```

## 每组视觉检查

- 是否正好 4 个主体，语义和顺序都正确；
- 是否存在额外装饰主体、文字、数字或水印；
- 主体是否越过象限中线或彼此连接；
- 背景是否均匀且接近 `#00FF00`；
- 是否有白边、阴影、反射或绿色主体；
- 缩小到目标 UI 尺寸后是否仍可辨识。

全部图板通过后再抠图。抠图后抽查复杂轮廓、细线、内部镂空和含叶片图标。
