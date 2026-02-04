<div align="center">
    <img src="Ice/Assets.xcassets/AppIcon.appiconset/icon_256x256.png" width=200 height=200>
    <h1>Ice</h1>
</div>

Ice 是一款强大的菜单栏管理工具。它的核心能力是隐藏与显示菜单栏项目，同时也提供丰富的外观与交互选项，目标是成为最灵活的菜单栏工具之一。

![Banner](docs/images/banner-zh.png)

[![Download](https://img.shields.io/badge/download-latest-brightgreen?style=flat-square)](https://github.com/jordanbaird/Ice/releases/latest)
![Platform](https://img.shields.io/badge/platform-macOS-blue?style=flat-square)
![Requirements](https://img.shields.io/badge/requirements-macOS%2014%2B-fa4e49?style=flat-square)
[![Sponsor](https://img.shields.io/badge/Sponsor%20%E2%9D%A4%EF%B8%8F-8A2BE2?style=flat-square)](https://github.com/sponsors/jordanbaird)
[![Website](https://img.shields.io/badge/Website-015FBA?style=flat-square)](https://icemenubar.app)
[![License](https://img.shields.io/github/license/jordanbaird/Ice?style=flat-square)](LICENSE)

English README → https://github.com/jordanbaird/Ice#readme

## 中文说明

Ice 是一款强大的菜单栏管理工具。它的核心能力是隐藏与显示菜单栏项目，同时也提供丰富的外观与交互选项，目标是成为最灵活的菜单栏工具之一。

### 安装

#### 手动安装

从 [原版英文最新版本](https://github.com/jordanbaird/Ice/releases/latest) 下载 `Ice.zip`，或从 [简体中文汉化版](https://github.com/mianm1986/Ice/releases/tag/v0.11.12-zh) 下载 `Ice.zip`。解压后将 `Ice.app` 拖到 `Applications` 文件夹。

#### Homebrew

```sh
brew install --cask jordanbaird-ice
```

说明：Homebrew 安装的是原版英文版本。

### 功能/路线图

#### 菜单栏项目管理

- [x] 隐藏菜单栏项目
- [x] “始终隐藏”分区
- [x] 鼠标悬停时显示隐藏项目
- [x] 点击菜单栏空白处显示隐藏项目
- [x] 滚动或滑动显示隐藏项目
- [x] 自动重新隐藏
- [x] 隐藏会与菜单栏项目重叠的应用菜单
- [x] 拖拽排序菜单栏项目
- [x] 在独立栏中显示隐藏项目（例如带刘海的 Mac）
- [x] 搜索菜单栏项目
- [x] 菜单栏项目间距（测试版）
- [ ] 菜单栏布局配置文件
- [ ] 独立分隔项
- [ ] 菜单栏项目分组
- [ ] 满足触发条件时显示项目

#### 菜单栏外观

- [x] 菜单栏着色（纯色与渐变）
- [x] 菜单栏阴影
- [x] 菜单栏边框
- [x] 自定义菜单栏形状（圆角与分割）
- [ ] 移除菜单栏背景
- [ ] 屏幕圆角
- [ ] 深色/浅色模式分别配置

#### 快捷键

- [x] 切换各菜单栏分区
- [x] 打开搜索面板
- [x] 启用/停用 Ice Bar
- [x] 显示/隐藏分区分隔图标
- [x] 切换应用菜单
- [ ] 启用/停用自动重新隐藏
- [ ] 临时显示单个菜单栏项目

#### 其他

- [x] 开机自启
- [x] 自动更新
- [ ] 菜单栏小组件

### 为什么只支持 macOS 14 及以上？

Ice 使用了从 macOS 14 开始提供的一些系统 API，因此目前没有支持更早版本的计划。

### 截图

#### 在菜单栏下方显示隐藏项目

![Ice Bar](https://github.com/user-attachments/assets/f1429589-6186-4e1b-8aef-592219d49b9b)

#### 拖拽排序菜单栏项目

![Menu Bar Layout](docs/images/menu-bar-layout-zh.png)

#### 自定义菜单栏外观

![Menu Bar Appearance](https://github.com/user-attachments/assets/8c22c185-c3d2-49bb-971e-e1fc17df04b3)

#### 菜单栏项目搜索

![Menu Bar Item Search](https://github.com/user-attachments/assets/d1a7df3a-4989-4077-a0b1-8e7d5a1ba5b8)

#### 菜单栏项目间距

![Menu Bar Item Spacing](https://github.com/user-attachments/assets/b196aa7e-184a-4d4c-b040-502f4aae40a6)

### 许可协议

Ice 使用 [GPL-3.0 license](LICENSE) 许可发布。

### 赞助

<a href="https://www.buymeacoffee.com/jordanbaird" target="_blank">
    <img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" alt="Buy Me A Coffee" style="height: 60px !important;width: 217px !important;">
</a>
