<div align="center">

<img src="assets/brand/logotype.svg" alt="MelonBanG" width="420">

<h3>追番？轻而易举！一个桌面应用全搞定!</h3>

<sub>基于 [Bangumi][bangumi] 的 Windows / macOS / Linux 原生追番客户端</sub>

<p>
  <a href="https://github.com/shirumesu/MelonBanG/releases"><img alt="版本" src="https://img.shields.io/github/v/release/shirumesu/MelonBanG?label=%E7%89%88%E6%9C%AC&color=22B388"></a>
  <a href="https://github.com/shirumesu/MelonBanG/releases"><img alt="下载量" src="https://img.shields.io/github/downloads/shirumesu/MelonBanG/total?label=%E4%B8%8B%E8%BD%BD&color=FF6B81"></a>
  <img alt="平台" src="https://img.shields.io/badge/%E5%B9%B3%E5%8F%B0-Windows%20%7C%20macOS%20%7C%20Linux-0F5C46">
  <a href="LICENSE"><img alt="许可证" src="https://img.shields.io/github/license/shirumesu/MelonBanG?label=%E8%AE%B8%E5%8F%AF%E8%AF%81&color=0F5C46"></a>
  <img alt="Flutter" src="https://img.shields.io/badge/Flutter-02569B?logo=flutter&logoColor=white">
</p>

<h4>
  <a href="#下载">下载</a> &nbsp;｜&nbsp;
  <a href="#常见问题">常见问题</a> &nbsp;｜&nbsp;
  <a href="#从源码构建">从源码构建</a> &nbsp;｜&nbsp;
  <a href="https://github.com/shirumesu/MelonBanG/issues">反馈问题</a>
</h4>

<sub>首页</sub><br>
<picture>
  <source media="(prefers-color-scheme: dark)" srcset=".github/screenshots/home-dark.webp">
  <img alt="MelonBanG 首页" src=".github/screenshots/home-light.webp" width="720">
</picture>

</div>

<div align="center">

<table>
<tr>
  <td width="50%" align="center"><sub>番剧详情</sub><br><img alt="番剧详情" src=".github/screenshots/detail.webp"></td>
  <td width="50%" align="center"><sub>资源搜索</sub><br><img alt="资源搜索" src=".github/screenshots/resources.webp"></td>
</tr>
<tr>
  <td width="50%" align="center"><sub>缓存</sub><br><img alt="缓存" src=".github/screenshots/cache.webp"></td>
  <td width="50%" align="center"><sub>播放器</sub><br><img alt="播放器" src=".github/screenshots/player.webp"></td>
</tr>
</table>
</div>

## 功能

- [x] 本季热度、每周时间表、今日更新、搜索功能
- [x] Bangumi 双向同步收藏、评分和观看进度
- [x] 资源聚合：在线、BT、pikpak
- [x] 内置 BT、硬件解码、Anime4K 超分引擎，支持边下边播
- [x] 弹幕支持弹弹play、b站、巴哈姆特，自主维护 Melon 的弹幕服务
- [x] 多色主题（我知道 Ai 感很重但我不会设计，在学习了）

## 下载

<p align="center">
  <a href="https://github.com/shirumesu/MelonBanG/releases/latest"><b>⬇ 下载最新版本</b></a> &nbsp;｜&nbsp;
  <a href="CHANGELOG.md">更新日志</a> &nbsp;｜&nbsp;
  <a href="https://github.com/shirumesu/MelonBanG/releases">全部版本</a>
</p>

[更新日志](CHANGELOG.md) 里有当前版本每个平台安装包的直接下载链接。装好以后应用会自己检查更新，在后台下载，重启即完成。

| 平台 | 要求 | 安装包 |
| --- | --- | --- |
| Windows | Windows 10 / 11，x64 | 安装版 `setup.exe`、便携版 `zip` |
| macOS | macOS 13 及以上，Apple 芯片 | `dmg` |
| Linux | x64，glibc 2.35 及以上 | `AppImage` |

> [!NOTE]
> 目前处于早期阶段，可能会遇到各种问题，欢迎在 [Issues](https://github.com/shirumesu/MelonBanG/issues) 反馈。

<details>
<summary><b>macOS 提示「无法验证开发者」</b></summary>

由于我没有钱购买 $99/1y 的苹果开发者订阅，被 Apple 鉴定为安卓用户，因此第一次打开会被拦下。把应用拖进「应用程序」后，在 **系统设置 → 隐私与安全性** 点 **仍要打开**，或在终端运行：

```sh
xattr -dr com.apple.quarantine /Applications/MelonBanG.app
```

更新后首次读取登录信息时会弹出钥匙串授权，选 **始终允许** 即可，钥匙串仅用于相关登录功能，不会上传任何你的密码和凭证。

</details>

## 常见问题

<details>
<summary><b>视频资源是从哪里来的？</b></summary>

MelonBanG 本身不存储、不提供任何视频。资源来自公开的 BT 网络、种子索引站、在线视频网站，以及你自己的 PikPak 账号。

</details>

<details>
<summary><b>不登录 Bangumi 能用吗？</b></summary>

能。浏览、搜索、下载和播放都不需要登录；不过登录后才能同步收藏和发送弹幕。

</details>

<details>
<summary><b>BT 会上传吗？</b></summary>

默认会适量做种，达到分享率 1 或做种 60 分钟后停止。可以在 **设置 → 下载与做种** 里改成停止分享。

</details>

<details>
<summary><b> BT 没速度</b></summary>

请检查代理设置，TUN / 全局模式的代理可能让 BT 连不上 Tracker 和 DHT。
增加一条直连规则即可，以 Clash 为例：

```yaml
- PROCESS-NAME,melonbang.exe,DIRECT   # Windows
- PROCESS-NAME,melonbang,DIRECT       # macOS、Linux
```

如果问题无法改善，请考虑更快速的 Pikpak 方式或者播放/缓存在线源。

</details>

<details>
<summary><b>怎么卸载？</b></summary>

Windows 和 macOS 在 **设置 → 更新与关于** 里卸载，可以选择是否保留数据和缓存；Linux 的 AppImage 直接删除文件即可。

</details>

## 从源码构建

需要 Flutter 稳定版。Windows 需要 Visual Studio C++ 桌面开发组件，macOS 需要 Xcode 和 Homebrew，Linux 需要 CMake 3.24 以上和以下开发包（以 Ubuntu 为例）：

```sh
sudo apt install clang ninja-build pkg-config libgtk-3-dev libmpv-dev libsecret-1-dev
```

```sh
git clone https://github.com/shirumesu/MelonBanG.git
cd MelonBanG
cp .env.service.example.json .env.service.json   # 可留空，留空时 Bangumi 登录和弹弹play 弹幕不可用
flutter pub get
flutter run -d windows   # 或 -d macos、-d linux
```

## 致谢与许可

- [Bangumi 番组计划][bangumi]、[弹弹play 开放平台][dandanplay]
- [media-kit](https://github.com/media-kit/media-kit) / [mpv](https://mpv.io)、[libtorrent](https://libtorrent.org)、[Anime4K][anime4k]
- [Resource Han Rounded](https://github.com/CyanoHao/Resource-Han-Rounded)、[Rclone](https://github.com/rclone/rclone)
- [Kazumi](https://github.com/Predidit/Kazumi)、[Animeko](https://github.com/open-ani/animeko)：同类优秀项目

本项目以 [GPL-3.0](LICENSE) 开源，第三方许可证见 [THIRD_PARTY.md](THIRD_PARTY.md)。

<sub>本项目仅供学习交流，使用者需遵守所在地的法律法规。MelonBanG 不对通过它获取的任何内容负责，也不收集任何使用数据。</sub>

## Star History

<a href="https://star-history.com/#shirumesu/MelonBanG&Date">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/svg?repos=shirumesu/MelonBanG&type=Date&theme=dark">
    <img alt="Star History" src="https://api.star-history.com/svg?repos=shirumesu/MelonBanG&type=Date" width="600">
  </picture>
</a>

## 贡献者

<a href="https://github.com/shirumesu/MelonBanG/graphs/contributors">
  <img alt="贡献者" src="https://contrib.rocks/image?repo=shirumesu/MelonBanG">
</a>


[bangumi]: https://bgm.tv
[dandanplay]: https://www.dandanplay.com
[anime4k]: https://github.com/bloc97/Anime4K
