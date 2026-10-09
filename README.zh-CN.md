<p align="right"><a href="README.md">English</a> | 简体中文</p>

# nc-amp

nc-amp —— 基于 Free Pascal/Lazarus 的 Windows 原生开源音乐播放器，经典 Winamp 风格界面，支持 MP3、FLAC、WAV、Ogg、Opus、M4A 等格式，拖入即随机循环播放。

[![License: GPL-3.0](https://img.shields.io/badge/license-GPL--3.0-blue.svg)](LICENSE)
[![Release](https://img.shields.io/github/v/release/shenmin/nc-amp)](https://github.com/shenmin/nc-amp/releases)
[![Platform: Windows](https://img.shields.io/badge/platform-Windows%20x64-0078d6.svg)](https://github.com/shenmin/nc-amp/releases)
[![Made with Lazarus](https://img.shields.io/badge/Lazarus%20%2F%20Free%20Pascal-Pascal-orange.svg)](https://www.lazarus-ide.org)

![nc-amp 截图](docs/screenshot.png)

## 功能特性

- **单文件绿色版**：Windows x64 下一个 exe 即可运行，无需安装，不产生额外文件。
- **支持格式**：MP3、FLAC、WAV、Ogg Vorbis、Opus、M4A / AAC（AAC 使用 Windows 自带的 Media Foundation 解码）。
- **拖入即播**：把文件或文件夹（递归扫描）拖到任一窗口，立即开始播放。
- **永远随机 + 循环**：每轮每首只播一次，播完后重新洗牌；新一轮不会以刚播完的曲目开头。
- **经典双窗口布局**：枪灰色外壳配灰绿色 LCD，实时 FFT 频谱，进度、音量、声道平衡，码率 / 采样率 / 立体声显示；独立播放列表窗口，可停靠、吸附、调整大小。
- **卷起（Shade）模式**：两个窗口都可卷成细条，保留迷你播放控制，在任意 DPI 下像素级对齐。
- **Per-Monitor-v2 高 DPI**：100%–250% 缩放下清晰锐利，跨显示器移动自动重新缩放；另有 1x / 1.5x / 2x 尺寸选项。
- **全面 Unicode**：中文文件名与标签（ID3v1 GBK、ID3v2、Vorbis 注释、MP4）。
- **托盘程序**：不占任务栏按钮；托盘图标配原生菜单；单实例运行（再次打开文件会交给已运行的实例播放）。
- **完全开源**：GPL-3.0-or-later，音频引擎仅由开源组件构建。

## 下载

在 [Releases](https://github.com/shenmin/nc-amp/releases) 下载 `nc-amp.exe` 直接运行，支持 Windows 10 / 11 x64。

程序未做代码签名，首次运行时 SmartScreen 可能提示“Windows 已保护你的电脑”：点击“更多信息”→“仍要运行”。

## 使用方法

- 把音乐文件或文件夹拖到窗口上，或按 **L** / 点击弹出按钮打开文件。
- 点击时间切换已播放 / 剩余时间；点击频谱开关可视化。
- 双击标题栏（或点击三角按钮）卷起 / 展开窗口。
- 把停靠的播放列表调到与主窗口差不多高，它会自动精确锁定为同一高度。
- 在任意位置右键可设置尺寸、播放列表、可视化、添加文件 / 文件夹、信息和退出。
- 左键单击托盘图标显示 / 隐藏窗口；右键托盘图标进行播放控制。
- 设置保存在 `%LOCALAPPDATA%\nc-amp\`（`nc-amp.ini`、`playlist.m3u8`）。

## 快捷键

| 按键 | 功能 |
|---|---|
| Z / X / C / V / B | 上一首 / 播放 / 暂停 / 停止 / 下一首 |
| L | 打开文件 |
| ← / → | 后退 / 前进 5 秒 |
| ↑ / ↓、Home / End | 移动播放列表选中项 |
| Enter | 播放选中曲目 |
| Del | 删除选中曲目 |
| Ctrl+A | 全选 |

## 从源码构建

nc-amp 在 Linux 上交叉编译（以下以 Debian / Ubuntu 为例）；也可在 Windows 上用 MSYS2 + Lazarus 构建。

依赖：

- Free Pascal 3.2.2（含 `x86_64-win64` 交叉 RTL，可在 FPC 源码中执行 `make crossinstall OS_TARGET=win64 CPU_TARGET=x86_64` 或使用 fpcupdeluxe 安装）与 Lazarus 4.x（`lazbuild`）
- MinGW-w64（`x86_64-w64-mingw32-gcc`、`x86_64-w64-mingw32-windres`）、CMake、curl

```sh
sudo apt install fpc lazarus gcc-mingw-w64-x86-64 binutils-mingw-w64-x86-64 cmake curl
git clone https://github.com/shenmin/nc-amp.git
cd nc-amp
./build.sh            # 生成 dist/nc-amp.exe
```

`build.sh` 依次完成：

1. `scripts/fetch-deps.sh` 下载固定版本的 libogg、libopus、opusfile 源码，并按 `third_party/deps.txt` 中的 SHA-256 校验。
2. `scripts/build-engine.sh` 将它们编译为静态库，并与 `third_party/` 中的 miniaudio、stb_vorbis 一起把音频引擎 `src/engine/ncaudio.c` 编译成 `src/engine/ncaudio.dll`。
3. `windres` 把清单、引擎和 LCD 字体打包进 `src/ncamp.res`，再用 `lazbuild` 构建 `src/nc-amp.lpi`。引擎 DLL 内嵌在 exe 中，启动时解压到 `%TEMP%`，因此最终只有一个文件。

`src/engine/ncaudio.dll` 和 `src/ncamp.res` 生成后，也可以直接在 Lazarus IDE 中打开 `src/nc-amp.lpi`。

目录结构：

```
src/            Pascal 源码、Lazarus 工程、资源
src/engine/     音频引擎（C）：miniaudio + stb_vorbis + opusfile + Media Foundation
third_party/    内置的单文件库与固定版本的依赖清单
assets/fonts/   IBM Plex Mono、Audiowide 字体（OFL）及标题字形生成脚本
assets/icon/    程序图标及其生成脚本
docs/           截图
scripts/        构建辅助脚本
```

## 致谢

- 音频：[miniaudio](https://miniaud.io)（含 dr_mp3 / dr_flac / dr_wav）、[stb_vorbis](https://github.com/nothings/stb)、[libopus、opusfile 与 libogg](https://opus-codec.org)，AAC 使用 Windows Media Foundation。
- 字体：[IBM Plex Mono](https://github.com/IBM/plex)（LCD 文字与图标）和 [Audiowide](https://fonts.google.com/specimen/Audiowide)（标题），均为 SIL OFL 1.1。
- 使用 [Free Pascal](https://www.freepascal.org) 与 [Lazarus](https://www.lazarus-ide.org) 构建。
- 外观致敬 Winamp 2.x；nc-amp 与 Winamp 无任何关联。

完整许可证文本见 [THIRD-PARTY-LICENSES.md](THIRD-PARTY-LICENSES.md)。

## 许可证

Copyright (C) 2026 Shen Min

nc-amp 是自由软件：你可以依据自由软件基金会发布的 GNU 通用公共许可证第 3 版或（由你选择）任何更新版本的条款，重新分发和/或修改它。详见 [LICENSE](LICENSE)。
