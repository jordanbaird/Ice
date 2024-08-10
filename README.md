<div align="center">
    <img src="Ice/Assets.xcassets/AppIcon.appiconset/icon_256x256.png" width=200 height=200>
    <h1>Ice</h1>
</div>

Ice is a powerful menu bar management tool. While its primary function is hiding and showing menu bar items, it aims to cover a wide variety of additional features to make it one of the most versatile menu bar tools available.

![Banner](https://github.com/jordanbaird/Ice/assets/90936861/e256575b-880c-49ee-90a1-b6eabd4a7868)

[![Download](https://img.shields.io/badge/download-latest-brightgreen?style=flat-square)](https://github.com/jordanbaird/Ice/releases/latest)
![Platform](https://img.shields.io/badge/platform-macOS-blue?style=flat-square)
![Requirements](https://img.shields.io/badge/requirements-macOS%2014%2B-fa4e49?style=flat-square)
[![Sponsor](https://img.shields.io/badge/Sponsor%20%E2%9D%A4%EF%B8%8F-8A2BE2?style=flat-square)](https://github.com/sponsors/jordanbaird)
[![Website](https://img.shields.io/badge/Website-015FBA?style=flat-square)](https://icemenubar.app)
[![License](https://img.shields.io/github/license/jordanbaird/Ice?style=flat-square)](LICENSE)

> [!NOTE]
> Ice is currently in active development. Some features have not yet been implemented. Download the latest release [here](https://github.com/jordanbaird/Ice/releases/latest) and see the roadmap below for upcoming features.

<a href="https://www.buymeacoffee.com/jordanbaird" target="_blank">
    <img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" alt="Buy Me A Coffee" style="height: 60px !important;width: 217px !important;">
</a>

## Install

### Manual Installation

Download the "Ice.zip" file from the [latest release](https://github.com/jordanbaird/Ice/releases/latest) and move the unzipped app into your `Applications` folder.

### Homebrew

Install Ice using the following command:

```sh
brew install jordanbaird-ice
```

## Usage

`Command` + drag your menu bar items to rearrange them.

![Rearranging](Resources/rearranging.gif)

## Features/Roadmap

### Menu bar item management

- [x] Hide menu bar items
- [x] "Always-hidden" menu bar section
- [x] Show hidden menu bar items when hovering over the menu bar
- [x] Show hidden menu bar items when an empty area in the menu bar is clicked
- [x] Show hidden menu bar items by scrolling or swiping in the menu bar
- [x] Automatically rehide menu bar items
- [x] Hide application menus when they overlap with shown menu bar items
- [x] Drag and drop interface to arrange individual menu bar items
- [x] Display hidden menu bar items in a separate bar (e.g. for MacBooks with the notch)
- [ ] Search menu bar items
- [ ] Custom menu bar item spacing
- [ ] Profiles for menu bar layout
- [ ] Menu bar item groups
- [ ] Show menu bar items when trigger conditions are met

### Menu bar appearance

- [x] Menu bar tint (solid and gradient)
- [x] Menu bar shadow
- [x] Menu bar border
- [x] Custom menu bar shapes (rounded and/or split)
- [ ] Remove background behind menu bar
- [ ] Rounded screen corners

### Hotkeys

- [x] Toggle individual menu bar sections
- [x] Toggle application menus
- [x] Show/hide section divider icons
- [ ] Temporarily show individual menu bar items
- [ ] Enable/disable auto rehide

### Other

- [x] Launch at login
- [x] Automatic updates
- [ ] Menu bar widgets

## Why does Ice only support macOS 14 and later?

Ice uses a number of system APIs that are available starting in macOS 14. As such, there are no plans to support earlier versions of macOS.

## Gallery

#### Arrange menu bar items in settings

![Arrange Menu Bar Items](https://github.com/user-attachments/assets/c2f4a3e2-f58e-45a0-b648-5f0af8fb84c0)

#### Show hidden menu bar items below the menu bar

![Ice Bar](https://github.com/user-attachments/assets/f1429589-6186-4e1b-8aef-592219d49b9b)

#### Customize the menu bar's appearance

![Menu Bar Appearance](https://github.com/user-attachments/assets/8c22c185-c3d2-49bb-971e-e1fc17df04b3)

#### Choose your own icon to show in the menu bar

![Custom Icon](https://github.com/user-attachments/assets/2f3668c1-9b48-46de-98e7-74bf9ff4fcce)

### Coming soon...

#### Menu bar item search

![Menu Bar Item Search](https://github.com/user-attachments/assets/ceca6fc6-4695-4a5c-ad64-3d92ce0dc234)

#### Custom menu bar item spacing

![Custom Menu Bar Item Spacing](https://github.com/user-attachments/assets/b196aa7e-184a-4d4c-b040-502f4aae40a6)

## Stargazers over time

[![Star History Chart](https://api.star-history.com/svg?repos=jordanbaird/Ice&type=Date)](https://star-history.com/#jordanbaird/Ice&Date)

## License

Ice is available under the [GPL-3.0 license](LICENSE).
