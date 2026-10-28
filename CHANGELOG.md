# MelonBanG 0.1.1-beta.1

> [!NOTE]
> 测试版：在 **设置 → 更新与关于** 把更新渠道改为测试版即可收到。各测试版的内容会在下一个正式版里汇总。

## 0.1.1-beta.1

- 番剧详情打开更快：剧集、角色、制作人员哪部分先到就先显示，不再等基础资料；顶部进度条只在详情出来之前显示，之后各区块各自显示加载
- 已保存的番剧详情过期后在后台整份刷新，不再先显示一半、各区块重新加载
- 连接复用更久，返回页面或再次打开详情时不用重新建立连接
- 悬停剧集格子、切换窗口时界面更流畅
- 应用内更新说明只显示你还没有的测试版内容

## 下载安装

| 系统 | 架构 | 类型 | GitHub |
| --- | --- | --- | --- |
| Windows 10 / 11 | x64 | 安装版 | [setup.exe](https://github.com/shirumesu/MelonBanG/releases/download/v0.1.1-beta.1/MelonBanG-0.1.1-beta.1-windows-x64-setup.exe) |
| Windows 10 / 11 | x64 | 便携版 | [zip](https://github.com/shirumesu/MelonBanG/releases/download/v0.1.1-beta.1/MelonBanG-0.1.1-beta.1-windows-x64.zip) |
| macOS 13 及以上 | Apple 芯片 | 磁盘映像 | [dmg](https://github.com/shirumesu/MelonBanG/releases/download/v0.1.1-beta.1/MelonBanG-0.1.1-beta.1-macos-arm64.dmg) |
| Linux | x64 | AppImage | [AppImage](https://github.com/shirumesu/MelonBanG/releases/download/v0.1.1-beta.1/MelonBanG-0.1.1-beta.1-linux-x64.AppImage) |

- **Windows**：安装版可以选择安装位置和下载位置，并会创建快捷方式；便携版解压即用。两者都能自动更新。
- **macOS**：没有 Apple 开发者签名，第一次打开会被拦下。把 MelonBanG 拖进「应用程序」后，到 **系统设置 → 隐私与安全性** 点 **仍要打开**，或在终端运行 `xattr -dr com.apple.quarantine /Applications/MelonBanG.app`。每次更新后第一次读取登录信息时会请求访问钥匙串，选 **始终允许** 即可。
- **Linux**：需要 glibc 2.35 及以上（Ubuntu 22.04、Debian 12、Fedora 36 或更新）。下载后 `chmod +x` 再运行；登录信息保存在系统钥匙环（GNOME Keyring、KWallet 等）里。播放器的画面暂时只能用 CPU 绘制（[上游问题](https://github.com/media-kit/media-kit/issues/1404)），所以 Linux 版没有超分辨率，CPU 占用也会高一些。
