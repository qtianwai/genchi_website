# 饭团正式形象 AI 提示词

## 使用目标

这套提示词用于生成饭团正式视觉稿，目标是替换当前项目中已接入的第一版 JSON 动画参考形象。

建议输出：

- 透明背景
- 单角色居中
- 1:1 比例
- 高分辨率
- 风格统一

建议模型：

- Midjourney
- DALL-E
- Stable Diffusion

## 基础统一提示词

```text
cute kawaii onigiri character, chibi style, rounded triangular rice ball body, soft white rice texture, deep green nori belt, big glossy bean eyes, pink blush cheeks, tiny mouth, tiny stubby arms and feet, sticker style, simple flat shading, clean silhouette, warm and adorable, san-x inspired softness, premium mobile app mascot, transparent background, centered composition, no text, no watermark
```

## 统一负面提示词

```text
ugly, scary, realistic human face, extra limbs, extra fingers, detailed background, text, watermark, logo, complex props, messy linework, dark horror mood, photorealistic, 3d render unless specified, low quality, cropped, duplicate character
```

## 各状态提示词

### 1. 默认闲逛 `fantuan_idle`

```text
cute kawaii onigiri mascot, chibi style, relaxed happy expression, soft smile, gentle floating pose, glossy bean eyes, pink blush, deep green nori belt, tiny arms and feet, premium app mascot illustration, transparent background, centered, simple flat shading
```

### 2. 饿了 `fantuan_hungry`

```text
cute kawaii onigiri mascot, very hungry expression, starry excited eyes, tiny open mouth with a drop of drool, eager pose, pink blush cheeks, deep green nori belt, tiny arms reaching forward, adorable food craving emotion, transparent background, centered
```

### 3. 犯困 `fantuan_sleepy`

```text
cute kawaii onigiri mascot, sleepy drowsy expression, half closed eyes, tiny round mouth, nodding pose, floating sleep bubbles, soft blush cheeks, deep green nori belt, relaxed tiny limbs, transparent background, centered, adorable and gentle
```

### 4. 兴奋 `fantuan_excited`

```text
cute kawaii onigiri mascot, super excited expression, sparkling bright eyes, open happy mouth, jumping pose, little star accents around the character, pink blush cheeks, deep green nori belt, energetic tiny limbs, transparent background, centered
```

### 5. 下雨 `fantuan_rainy`

```text
cute kawaii onigiri mascot, rainy day mood, slightly shivering pose, sleepy worried eyes, tiny flat mouth, holding a tiny blue umbrella or leaf umbrella, huddled body language, deep green nori belt, transparent background, centered
```

### 6. 吃卡 `fantuan_eating`

```text
cute kawaii onigiri mascot, eating happily, wide open mouth then satisfied chewing feeling, delighted closed smiling eyes, tiny crumbs, blushing cheeks, deep green nori belt, satisfied belly-pat emotion, transparent background, centered
```

### 7. 开心 `fantuan_happy`

```text
cute kawaii onigiri mascot, extremely happy expression, smiling crescent eyes, rosy cheeks, swaying body pose, tiny arms raised, affectionate adorable mood, deep green nori belt, premium mascot illustration, transparent background, centered
```

### 8. 饿瘪 `fantuan_starving`

```text
cute kawaii onigiri mascot, exhausted starving expression, flattened shrunken body, x eyes, tiny flat mouth, sweat drop, weak pose, deep green nori belt, still adorable not scary, transparent background, centered
```

### 9. 点击反馈 `fantuan_tap`

```text
cute kawaii onigiri mascot, playful tap reaction, one eye wink, smiling mouth, bouncy pose, little question bubble above head, pink blush cheeks, deep green nori belt, lively mascot illustration, transparent background, centered
```

## 产出筛选标准

- 角色轮廓必须稳定，不能每个状态像不同角色
- 海苔腰带位置和比例尽量一致
- 眼睛必须足够大，适合小尺寸图标显示
- 嘴巴不能太复杂，否则转 Lottie 时不稳定
- 尽量保持纯色块和少量阴影，方便矢量化

## 替换到项目的建议流程

1. 每个状态先生成 2 到 4 张备选图。
2. 从中选出最统一的一组，作为同一角色的标准参考。
3. 基于参考图在 Figma / LottieFiles Creator / After Effects 中重绘成矢量形状。
4. 导出后直接覆盖：
   - `ios/FoodMap/genchi/genchi/Resources/Animations/fantuan_idle.json`
   - `ios/FoodMap/genchi/genchi/Resources/Animations/fantuan_hungry.json`
   - `ios/FoodMap/genchi/genchi/Resources/Animations/fantuan_sleepy.json`
   - `ios/FoodMap/genchi/genchi/Resources/Animations/fantuan_excited.json`
   - `ios/FoodMap/genchi/genchi/Resources/Animations/fantuan_rainy.json`
   - `ios/FoodMap/genchi/genchi/Resources/Animations/fantuan_eating.json`
   - `ios/FoodMap/genchi/genchi/Resources/Animations/fantuan_happy.json`
   - `ios/FoodMap/genchi/genchi/Resources/Animations/fantuan_starving.json`
   - `ios/FoodMap/genchi/genchi/Resources/Animations/fantuan_tap.json`

## 当前项目现状

当前项目已经：

- 接入官方 `Lottie` Swift Package
- 将饭团视图切换到真实 `Lottie` 渲染路径
- 提供第一版可运行的 JSON 动画资源

后续如果拿到更高质量的 AI 静态图，只需要覆盖同名 JSON 资源，不需要重写业务代码。
