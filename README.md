# 玺录屏 XiScreenRecorder

> macOS 原生屏幕录制工具，基于 FFmpeg + SwiftUI 构建。

[![Platform](https://img.shields.io/badge/platform-macOS%2013%2B-blue)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-5.9%2B-orange)](https://swift.org)
[![License](https://img.shields.io/badge/license-MIT-green)](#)

## ✨ 功能特性

- 🖥 **屏幕录制** — 录制整个屏幕或自定义框选区域
- 🔊 **系统声音录制** — 录制系统音频（需要虚拟音频设备）
- 🎙 **麦克风控制** — 录制过程中可随时开启/关闭，支持多设备选择
- 🎬 **多种录制模式**:
  - 仅录制屏幕
  - 屏幕 + 系统声音
  - 仅录制系统音频
- 📐 **区域选择** — 拖拽框选自定义录制区域
- ⚙️ **丰富的设置**:
  - 视频质量 (低/中/高)
  - 帧率 (15/24/30/60 FPS)
  - 输出格式 (MP4/MOV/MKV/MP3/AAC)
- 🎨 **仿系统设置 UI** — NavigationSplitView 左右分栏，无标题栏设计
- 📋 **实时日志** — 查看 FFmpeg 录制详情
- ⬇️ **自动安装 FFmpeg** — 首次启动自动检测，支持 Homebrew 或静态包安装

## 📋 前置要求

### 1. 安装 FFmpeg

```bash
brew install ffmpeg
```

### 2. 系统音频录制（可选）

macOS 默认不支持直接录制系统声音，需要安装虚拟音频设备。本应用支持以下驱动（任选其一）：

#### 方案 A：BlackHole（推荐，免费开源）

```bash
brew install blackhole-2ch
```

#### 方案 B：VB-Cable（免费）

1. 从 [https://vb-audio.com/Cable/](https://vb-audio.com/Cable/) 下载 macOS 版本
2. 运行安装器，安装完成后重启电脑
3. 安装后会出现 "VB-Cable" 虚拟音频设备

#### 方案 C：Soundflower

```bash
brew install --cask soundflower
```

#### 配置多路输出设备（通用步骤）

安装虚拟音频驱动后，需要配置多路输出设备才能同时听到声音并录制：

1. 打开 **音频 MIDI 设置**（`/Applications/Utilities/Audio MIDI Setup.app`）
2. 点击左下角 "+" → **创建多输出设备**
3. 勾选虚拟音频设备（BlackHole 2ch / VB-Cable）和你的扬声器/耳机
4. 在 **系统设置 → 声音 → 输出** 中选择该多输出设备
5. 在本应用的音频设置中选择对应的虚拟设备作为"系统音频"

> 💡 应用会自动检测已安装的虚拟音频设备并优先选中。

### 3. 屏幕录制权限

首次运行时，macOS 会请求屏幕录制权限。请在 **系统设置 → 隐私与安全 → 屏幕录制** 中允许。

## 🚀 编译运行

```bash
cd ScreenRecorder
swift build
swift run
```

或者用 Xcode 打开：

```bash
open Package.swift
```

## � 打包 DMG

```bash
chmod +x scripts/build-dmg.sh
./scripts/build-dmg.sh
# 产物: dist/玺录屏-1.0.0.dmg
```

## �🛠 构建发布版本

```bash
swift build -c release
# 可执行文件位于 .build/release/ScreenRecorder
```

## 📁 项目结构

```
Sources/
├── App.swift                    # 应用入口
├── ContentView.swift            # 主界面 UI（NavigationSplitView 分栏）
├── Models.swift                 # 数据模型和枚举
├── FFmpegHelper.swift           # FFmpeg 工具类 & 自动安装
├── RegionSelector.swift         # 区域框选功能（NSPanel overlay）
└── ScreenRecorderManager.swift  # 录制管理核心逻辑
scripts/
└── build-dmg.sh                 # 打包 DMG 脚本
```

## 📝 使用说明

1. 选择录制模式（屏幕 / 屏幕+声音 / 仅音频）
2. 选择捕获区域（全屏 / 自定义区域）
3. 点击底部麦克风图标，选择麦克风设备并开启
4. 调整视频质量、帧率和输出格式
5. 点击「开始录制」按钮
6. 点击「停止录制」结束录制
7. 文件自动保存到指定路径（默认为桌面）

## ⚠️ 注意事项

- **录制系统声音必须安装虚拟音频驱动**（BlackHole / VB-Cable / Soundflower），macOS 原生不支持采集系统音频
- 安装虚拟音频驱动后，务必在「音频 MIDI 设置」中创建**多输出设备**，否则你自己会听不到声音
- 应用使用 **设备名称** 而非索引来指定 FFmpeg 的 avfoundation 输入，更加可靠
- 同时录制系统音频 + 麦克风时，使用 FFmpeg 的 **amix 滤镜** 实时混合两路音轨
- 自定义区域录制使用 FFmpeg 的 crop 滤镜实现
- 麦克风状态变更将在下次录制时生效（FFmpeg 限制）
- 需要 macOS 13 (Ventura) 或更高版本

## 🔊 音频录制原理

```
                    ┌──────────────────┐
  系统声音 ────────→│ 多输出设备        │──→ 扬声器/耳机 (你能听到)
                    │  (Audio MIDI)     │──→ BlackHole   (FFmpeg 能录到)
                    └──────────────────┘
  
  FFmpeg 输入:
    屏幕+系统音频:  -i "Capture screen 0:BlackHole 16ch"
    纯系统音频:     -i "none:BlackHole 16ch"
    系统音频+麦克风: amix 滤镜混合两路
```
