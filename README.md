<div align="center">

<img src="assets/brand/logotype.svg" alt="MelonBanG" width="420">

<p><b>找番、追番、下番、看番，一个桌面应用全搞定。</b></p>

<p>
  <a href="https://github.com/shirumesu/MelonBanG/releases"><img alt="版本" src="https://img.shields.io/github/v/release/shirumesu/MelonBanG?include_prereleases&label=%E7%89%88%E6%9C%AC&color=22B388"></a>
  <a href="https://github.com/shirumesu/MelonBanG/releases"><img alt="下载量" src="https://img.shields.io/github/downloads/shirumesu/MelonBanG/total?label=%E4%B8%8B%E8%BD%BD&color=FF6B81"></a>
  <img alt="平台" src="https://img.shields.io/badge/%E5%B9%B3%E5%8F%B0-Windows%20%7C%20macOS-0F5C46">
  <a href="LICENSE"><img alt="许可证" src="https://img.shields.io/github/license/shirumesu/MelonBanG?label=%E8%AE%B8%E5%8F%AF%E8%AF%81&color=0F5C46"></a>
  <img alt="Flutter" src="https://img.shields.io/badge/Flutter-02569B?logo=flutter&logoColor=white">
</p>

<p>
  <a href="#下载">下载</a> ·
  <a href="#功能">功能</a> ·
  <a href="#常见问题">常见问题</a> ·
  <a href="#从源码构建">从源码构建</a>
</p>

<picture>
  <source media="(prefers-color-scheme: dark)" srcset=".github/screenshots/home-dark.webp">
  <img alt="MelonBanG 首页" src=".github/screenshots/home-light.webp">
</picture>

</div>

MelonBanG 是一个原生桌面追番客户端。番剧信息和收藏来自 [Bangumi][bangumi]，同一次搜索里同时查本地缓存、在线源和 BT 种子站，选好资源就能边下边播，播放时叠加多个平台的弹幕。

不登录、不下载也能用：浏览新番、看时间表、在本地记录追番进度都可以。

## 功能

### 发现与追番

- **首页**：本季热度榜、继续观看（显示看到第几话、还剩几分钟）、今日更新时间线（带「现在」刻度）
- **每周时间表**：按 UTC+8 播出时间排列
- **收藏与进度**：登录 Bangumi 后双向同步收藏、评分、标签、吐槽和观看进度；离线时的修改先排队，联网后再上传

### 番剧详情

<img alt="番剧详情" src=".github/screenshots/detail.webp">

- 一屏放下简介、评分、全部剧集和「我的收藏」：剧集格点一下就播放（已缓存时直接打开），没缓存就去找资源
- 长按并拖过剧集格可以一次标记多话已看；星级、标签、收藏状态改完立即保存，并且可以撤销
- 角色与声优、制作人员、收藏统计、吐槽 / 评论 / 讨论
- 下一话还没播出时，播放按钮会显示「周四 20:30 更新第 5 话」

### 资源搜索

<img alt="资源搜索" src=".github/screenshots/resources.webp">

- 一次搜索合并 **本地缓存**、**在线源**和 **BT**（蜜柑计划、动漫花园），PikPak 能秒下的种子单独列出
- 从标题里识别字幕组、画质、编码、字幕语言和形式（简繁 / 内封 / 内嵌），可以按这些条件多选筛选
- 同一字幕组的单集发布会自动合并成一个系列条目，按话展开；支持按 `1-3, 5, 8-12` 这样的范围批量下载
- 标出「推荐」资源，以及这部番「上次选择」的来源

### 缓存

<img alt="缓存" src=".github/screenshots/cache.webp">

- **BT**：内置 libtorrent 引擎，边下边播（按播放位置优先下载），做种策略可以选「停止 / 适量 / 持续分享」
- **PikPak**：用你自己的账号走云端加速，在 PikPak 的离线库里有的资源可以秒下
- **在线源**：HLS 和直链也能下载到本地
- 同一部番的多个任务合成一组，「继续播放」直接从上次看到的地方接着放

### 播放器

<img alt="播放器" src=".github/screenshots/player.webp">

- 基于 mpv：支持硬件解码、ASS 特效字幕、倍速，可以用 [Anime4K][anime4k] 实时超分
- **弹幕**：[弹弹play][dandanplay]、哔哩哔哩、巴哈姆特动画疯，加上 MelonBanG 自己的弹幕服务（登录 Bangumi 就能发送）；简繁写法不同的重复弹幕会合并成一条
- 根据视频内嵌章节自动跳过片头片尾，自动连播下一话，可选看到 80% 自动标记已看
- 侧栏可以切换剧集、换资源、看本集讨论、调整弹幕

### 外观

- 浅色 / 深色 / 跟随系统；六种主题色，或者跟随系统强调色
- 可选「封面取色」：详情页和播放器按番剧封面配色
- 动效会遵循系统的「减少动态效果」设置

## 下载

前往 [Releases](https://github.com/shirumesu/MelonBanG/releases) 下载最新版本。应用内置更新检查，有新版本时会在后台下载，重启后完成更新。

| 平台 | 要求 | 文件 |
| --- | --- | --- |
| Windows | Windows 10 / 11，x64 | `MelonBanG-<版本>-windows-x64-setup.exe`（安装版）<br>`MelonBanG-<版本>-windows-x64.zip`（便携版） |
| macOS | macOS 13 及以上，Apple 芯片 | `MelonBanG-<版本>-macos-arm64.dmg` |

> [!NOTE]
> 目前处于 alpha 阶段（`1.0.0-alpha.N`），可能会遇到问题，欢迎在 [Issues](https://github.com/shirumesu/MelonBanG/issues) 反馈。

<details>
<summary><b>macOS 首次打开提示「无法验证开发者」</b></summary>

MelonBanG 没有加入 Apple 开发者计划，安装包只做了 ad-hoc 签名、没有公证，所以第一次打开会被 Gatekeeper 拦下。把应用拖进「应用程序」文件夹后，任选一种方式放行：

- 打开 **系统设置 → 隐私与安全性**，在页面下方点 **仍要打开**
- 或在终端运行：

  ```sh
  xattr -dr com.apple.quarantine /Applications/MelonBanG.app
  ```

每次更新后第一次读取 Bangumi / PikPak 登录信息时，系统会弹出钥匙串授权窗口，选 **始终允许** 即可。

</details>

## 常见问题

<details>
<summary><b>视频资源是从哪里来的？</b></summary>

MelonBanG 本身不存储、不提供任何视频。资源来自公开的 BT 网络、种子索引站、在线视频网站，以及你自己的 PikPak 账号。番剧信息来自 Bangumi，弹幕来自各弹幕平台。

</details>

<details>
<summary><b>BT 会上传吗？</b></summary>

会。默认是「适量分享」：下载完成后继续做种，分享率达到 1 或做种满 60 分钟就停止。上传限速默认 1 MiB/s。这些都可以在 **设置 → 下载与做种** 里修改，也可以改成「停止分享」。

</details>

<details>
<summary><b>开着代理时 BT 一直没速度</b></summary>

TUN / 全局模式的代理（比如 Clash）可能把 BT 流量转给不支持 UDP 的节点，结果连不上任何 Tracker 和 DHT。播放器的缓冲提示里也会提到这种情况。解决方法是给 MelonBanG 加一条直连规则，例如：

```yaml
- PROCESS-NAME,melonbang.exe,DIRECT
```

</details>

<details>
<summary><b>不登录 Bangumi 能用吗？</b></summary>

能。浏览、搜索、时间表、本地追番进度、下载和播放都不需要登录。登录后才能同步 Bangumi 收藏、发送弹幕。

</details>

<details>
<summary><b>怎么卸载？数据存在哪？</b></summary>

在 **设置 → 更新与关于** 里可以直接卸载，Windows 也可以从系统的「应用」列表卸载。卸载时可以选择保留数据，或者连同数据库、设置和缓存的视频一起删除。数据和缓存目录在首次启动时选择，之后可以在 **设置 → 存储** 里迁移。

</details>

## 从源码构建

需要 Flutter 稳定版（CI 使用 3.47.5）。Windows 需要 Visual Studio 的 C++ 桌面开发组件；macOS 需要 Xcode 和 Homebrew。

```sh
git clone https://github.com/shirumesu/MelonBanG.git
cd MelonBanG
cp .env.service.example.json .env.service.json   # 填入你自己的 Bangumi / 弹弹play 应用凭据，可留空
flutter pub get
flutter run -d windows   # 或 -d macos
```

凭据留空时，Bangumi 登录和弹弹play 弹幕不可用，其余功能照常。打包 Release 用 `scripts/build.ps1`（Windows）或 `scripts/package-macos.sh`（macOS）。第一次原生构建会编译 libtorrent，耗时较长。

## 致谢

- [Bangumi 番组计划][bangumi]：番剧数据、收藏与社区
- [弹弹play 开放平台][dandanplay]：弹幕匹配与弹幕数据
- [media-kit](https://github.com/media-kit/media-kit) / [mpv](https://mpv.io)：视频播放
- [libtorrent](https://libtorrent.org) 与 [libtorrent_flutter](https://pub.dev/packages/libtorrent_flutter)：BT 引擎
- [Anime4K][anime4k]：实时超分辨率着色器
- [Resource Han Rounded](https://github.com/CyanoHao/Resource-Han-Rounded)：界面字体
- [Rclone](https://github.com/rclone/rclone)：PikPak 协议参考
- [Kazumi](https://github.com/Predidit/Kazumi)、[Animeko](https://github.com/open-ani/animeko)：同类优秀项目，给了很多启发

第三方组件的许可证见 [THIRD_PARTY.md](THIRD_PARTY.md)。

## 免责声明

本项目仅供学习交流，使用者需遵守所在地的法律法规，不得用于侵犯他人知识产权。MelonBanG 不对通过它获取的任何内容负责。

MelonBanG 不收集任何使用数据，也不包含遥测。

## 许可证

[GPL-3.0](LICENSE)

[bangumi]: https://bgm.tv
[dandanplay]: https://www.dandanplay.com
[anime4k]: https://github.com/bloc97/Anime4K
