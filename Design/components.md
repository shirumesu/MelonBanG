# 共用组件

新界面优先组合下面这些组件；需要新组件时，先确认它会在两个以上的地方用到，再放进 `lib/ui/core/`。

## 容器

| 组件 | 文件 | 用法 |
| --- | --- | --- |
| `PageScroll` | `page_widgets.dart` | 普通页面的滚动容器，自带左右边距 |
| `MelonPanel` | `page_widgets.dart` | 白色圆角面板；传 `onTap` 后整块可点 |
| `SectionTitle` | `page_widgets.dart` | 区块标题：图标、标题、副标题、右侧操作；`top` 控制上方留白，页面第一个区块用 0 |
| `EmptyState` | `page_widgets.dart` | 空、出错、无结果；必须说明原因，能补救时给一个操作 |
| `SettingRow` | `settings/settings_page.dart` | 设置行：左边标题和说明，右边控件 |

## 海报与封面

| 组件 | 用法 |
| --- | --- |
| `SubjectCover` | 所有封面图都用它：加载中和缺图时显示带首字的渐变占位 |
| `SubjectPoster` | 竖版海报卡，番名压在封面底部；`badge` 用于“今日更新”这类强调标签 |
| `SubjectPosters` | 网格（搜索结果、追番）或横栏（`horizontal: true`） |
| `HorizontalPosters` | 横向滚动栏，悬停边缘时出现翻页按钮；可混排不同卡片 |

海报的悬停效果只作用在封面上，不染色下方的文字区。

## 标签与状态

- `MelonBadge`：彩色小标签，底色是颜色的 13%（深色 20%）透明度。用于平台、季度、集数、“在追”。
- 封面上的标签用实色底和白字（排名、“继续第 N 话”、“今日更新”）。
- 资源标题标注：集数标签在最前面，用主色容器；集数冲突用错误色容器；其余标注用浅灰底。

## 控件

| 组件 | 用法 |
| --- | --- |
| `FilledButton` | 每个区域最多一个主要操作（搜索、下载、登录） |
| `OutlinedButton` | 次要但重要的操作（退出登录、立即同步） |
| `TextButton` | 链接式操作（“全部追番 →”“时间表 →”“清除筛选”） |
| `MelonSegmentedControl` | 2–5 个互斥选项，例如画质、收藏状态 |
| `MelonChoiceMenu` | 选项较多或较长的单选，例如来源分组 |
| `FilterChip` | 可多选的开关，例如资源站显示 / 隐藏、别名 |
| `Switch` | 布尔设置 |

资源站标签：显示时是勾选状态，带结果数，部分失败时用黄色补充“部分名称失败”；点击后变为“已隐藏”（划掉名称、显示隐藏图标），再点恢复。

## 反馈

- `ActionFeedback` + `FeedbackButton`：刷新、同步这类操作，在按钮原位显示进行中 / 已完成。
- `FeedbackIssue`：操作失败时在区块顶部给出原因和重试。
- 全局 `SnackBar` 只用于没有固定位置的错误。
