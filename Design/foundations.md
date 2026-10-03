# 基础样式

数值均以 `lib/ui/core/theme.dart` 为准。

## 颜色

浅色和深色主题共用同一套角色，组件只引用 `ColorScheme` 角色或下面的具名常量，不写一次性的颜色值。

| 角色 | 浅色 | 深色 | 用途 |
| --- | --- | --- | --- |
| 页面背景 `scaffoldBackgroundColor` | `#F3F5F4` | `#151922` | 中性灰底，带极轻的绿色倾向 |
| 卡片 `surface` | `#FBFCFB` | `#1E2430` | 面板、列表、输入框底 |
| 主色 `primary` | `#168364` | `#73D7B2` | 链接、选中、已更新、进度 |
| 主色容器 `primaryContainer` | `#B8EDD5` | `#304F42` | 主要按钮、选中行底色 |
| 正文 `onSurface` | `#263833` | `#E7EEF1` | 标题与正文 |
| 次要文字 `onSurfaceVariant` | `#6F7D78` | `#A0AFB9` | 说明、元数据、待更新 |
| 分隔线 `outlineVariant` | `#E1E8E3` | `#354052` | 列表分隔、时间线未到达部分 |

具名强调色（`theme.dart` 顶部常量）：

| 常量 | 值 | 用途 |
| --- | --- | --- |
| `mint` | `#22B388` | 品牌色、“继续播放”标签、追番数量 |
| `coral` | `#FF6B81` | 热度、“今日更新”标签、“现在”时间线标记 |
| `gold` | `#FFB83D` | 评分星、聚光灯里的排名 |
| `sky` | `#8BBCF6` | 平台 / 集数标签、想看 |
| `grape` | `#B6A4F0` | 看过、默认头像 |

收藏状态颜色固定：在看 mint、想看 sky、搁置 gold、看过 grape、抛弃 coral（`collectionColor`）。

## 字体

- 字族：**思源柔黑 Resource Han Rounded**（打包在 `assets/fonts/`，OFL 授权），缺字回退到微软雅黑 / 苹方。
- 只打包 Regular（400）和 Bold（700）。代码里写 w500 会显示为 Regular，w600–w900 显示为 Bold；新代码请直接用 w400 或 w700。
- 12px 及以下的中文不要用 Bold：笔画多的字（编、辑、资）在桌面缩放下会糊成一团，和笔画少的字放在一起像换了字体。文字按钮（13px）和标签芯片（12px）用 Regular，靠颜色和底色区分。
- 数字对齐的位置（时间、大小、日期、“2 / 8”）加 `FontFeature.tabularFigures()`。

| 用途 | 字号 | 字重 |
| --- | --- | --- |
| 页面 / 分类标题 `titleLarge` | 22 | Bold |
| 区块标题 `titleMedium` | 17 | Bold |
| 面板内小标题 `titleSmall` | 13 | Bold |
| 正文 | 13–14 | Regular |
| 说明、元数据 `bodySmall` | 12 | Regular，次要文字色 |
| 徽章 | 11 | Bold（只放短词、数字） |
| 标签芯片 | 12 | Regular |
| 文字按钮（链接式操作） | 13 | Regular，主色 |
| 聚光灯番名 | 24 | Bold |

## 间距

使用 4 的倍数，常量在 `Gap`：`xs 4 · sm 8 · md 12 · lg 16 · xl 24 · xxl 32`。

- 页面左右边距 `pageGutter` = 24。
- 同一组内的元素用 `sm` / `md`；面板内边距 `lg`–`xl`；区块之间 `xl`–`xxl`。
- 首页上下两段之间用 `xxl`，比其他页面更松，避免“挤”。

## 尺寸

| 常量 | 值 | 说明 |
| --- | --- | --- |
| `titleBarHeight` | 44 | 自绘标题栏 |
| `sidebarWidth` | 208 | 主侧栏 |
| `homeSideColumnWidth` | 336 | 首页右栏（榜单、今日更新） |
| 海报横栏 | 宽 188，高 292 | `HorizontalPosters`，含海报下方信息 |
| 资源表格 | 宽于 760 时显示分列 | `resourceTableWidth` |

## 圆角与阴影

- 圆角：海报 14、面板 16、控件 12、徽章 8。同一层级只用一种圆角。
- 阴影只给海报（`posterShadows`）和浮层菜单；面板靠底色与页面区分，不加阴影和描边。
- 深色下阴影几乎看不见，浮层菜单底色改用 `surfaceContainerHigh`（`menuSurface()`），否则会和下面的面板融在一起。
- 放在面板上的未激活控件（筛选按钮、开关标签）同样用 `surfaceContainerHigh` 底，和输入框一致，否则看起来像纯文字。

## 动效

- 时长通过 `motionDuration(context, ms)` 取得，系统开启“减少动画”时自动变为 0。
- 常用时长：悬停 / 按下 80–150ms，切换内容 180–220ms，展开收起 220ms。
- 动画只用于状态变化的反馈（聚光灯切换淡入、行展开、悬停放大播放按钮），不做装饰性循环动画。
