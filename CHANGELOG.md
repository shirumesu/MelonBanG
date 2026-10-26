# MelonBanG 0.1.0

> [!NOTE]
> 第一个公开版本。主要功能都能用了，但肯定还有不少问题，遇到了欢迎到 [Issues](https://github.com/shirumesu/MelonBanG/issues) 反馈。0.x 阶段本地数据的格式还可能调整，有不兼容的改动时会在这里提前写明。
>
> 之前装过 1.0.0-alpha.1 的话，它不会自动更新到 0.1.0，请从下面重新下载安装，数据会保留。

## 功能

- 本季热度、每周放送表、今日更新与条目搜索
- 登录 Bangumi 后双向同步收藏、评分和观看进度；不登录也能在本机记录追番
- 资源聚合：在线视频、BT 与 PikPak，按集数自动匹配；动漫花园与蜜柑计划的同一个种子合并显示
- 字幕组偏好：拖动排序，偏好字幕组的发布优先推荐，也可以只显示它们
- 内置 BT 下载，边下边播，可设置做种分享
- 播放器：硬件解码、Anime4K 超分辨率、ASS 字幕、跳过片头片尾
- 弹幕：弹弹play、哔哩哔哩、巴哈姆特，以及登录 Bangumi 后可发送的 MelonBanG 弹幕
- 应用内自动更新：后台下载并校验签名，重启即完成
- 多色主题，浅色与深色

## 下载安装

| 系统 | 架构 | 类型 | GitHub |
| --- | --- | --- | --- |
| Windows 10 / 11 | x64 | 安装版 | [setup.exe](https://github.com/shirumesu/MelonBanG/releases/download/v0.1.0/MelonBanG-0.1.0-windows-x64-setup.exe) |
| Windows 10 / 11 | x64 | 便携版 | [zip](https://github.com/shirumesu/MelonBanG/releases/download/v0.1.0/MelonBanG-0.1.0-windows-x64.zip) |
| macOS 13 及以上 | Apple 芯片 | 磁盘映像 | [dmg](https://github.com/shirumesu/MelonBanG/releases/download/v0.1.0/MelonBanG-0.1.0-macos-arm64.dmg) |
| Linux | x64 | AppImage | [AppImage](https://github.com/shirumesu/MelonBanG/releases/download/v0.1.0/MelonBanG-0.1.0-linux-x64.AppImage) |

- **Windows**：安装版可以选择安装位置和下载位置，并会创建快捷方式；便携版解压即用。两者都能自动更新。
- **macOS**：没有 Apple 开发者签名，第一次打开会被拦下。把 MelonBanG 拖进「应用程序」后，到 **系统设置 → 隐私与安全性** 点 **仍要打开**，或在终端运行 `xattr -dr com.apple.quarantine /Applications/MelonBanG.app`。每次更新后第一次读取登录信息时会请求访问钥匙串，选 **始终允许** 即可。
- **Linux**：需要 glibc 2.35 及以上（Ubuntu 22.04、Debian 12、Fedora 36 或更新）。下载后 `chmod +x` 再运行；登录信息保存在系统钥匙环（GNOME Keyring、KWallet 等）里。播放器的画面暂时只能用 CPU 绘制（[上游问题](https://github.com/media-kit/media-kit/issues/1404)），所以 Linux 版没有超分辨率，CPU 占用也会高一些。
