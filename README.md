<div align="center">
    <img src="Ice/Assets.xcassets/AppIcon.appiconset/icon_256x256.png" width=200 height=200>
    <h1>Ice — Free & Open-Source Menu Bar Manager for macOS</h1>
    <p>Hide and organize menu bar icons on your Mac. The best <strong>free Bartender alternative</strong> — also a great <strong>Hidden Bar</strong> and <strong>Vanilla alternative</strong> — focused on stability and a smooth, distraction-free experience.<br>✅ <strong>Fully supports macOS 27</strong></p>
</div>

![Ice menu bar manager for macOS — hide and organize menu bar icons](./Resources/Image/banner.png)

<div align="center">

[![Download](https://img.shields.io/badge/download-latest-brightgreen?style=flat-square)](https://github.com/cavaldos/Ice/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/cavaldos/Ice/total?style=flat-square)](https://github.com/cavaldos/Ice/releases)
![Platform](https://img.shields.io/badge/platform-macOS-blue?style=flat-square)
![Requirements](https://img.shields.io/badge/requirements-macOS%2014%2B-fa4e49?style=flat-square)
![macOS 27](https://img.shields.io/badge/macOS_27-fully_supported-brightgreen?style=flat-square)
[![GitHub stars](https://img.shields.io/github/stars/cavaldos/Ice?style=flat-square)](https://github.com/cavaldos/Ice/stargazers)
[![GitHub forks](https://img.shields.io/github/forks/cavaldos/Ice?style=flat-square)](https://github.com/cavaldos/Ice/network/members)
[![Website](https://img.shields.io/badge/Website-015FBA?style=flat-square)](https://icemenubar.app)
[![License](https://img.shields.io/github/license/cavaldos/Ice?style=flat-square)](LICENSE)
[![Sponsor](https://img.shields.io/badge/Sponsor%20%E2%9D%A4%EF%B8%8F-8A2BE2?style=flat-square)](https://ko-fi.com/calvados)

<br>

<a href="https://ko-fi.com/calvados" target="_blank">
    <img src="https://storage.ko-fi.com/cdn/kofi5.png?v=6" alt="Support me on Ko-fi" style="height: 60px !important;width: 217px !important;">
</a>

</div>

> [!NOTE]
> Ice is in active development. Grab the latest build from the [releases page](https://github.com/cavaldos/Ice/releases/latest).

> [!TIP]
> ✅ **Fully supports macOS 27** — tested and ready for the latest macOS, all the way back to macOS 14 Sonoma.

## Install

**Homebrew** (recommended — updates with `brew upgrade`):

```bash
brew tap cavaldos/tap
brew install cavaldos/tap/ice
```

**Manual:**

1. Download `Ice.zip` from the [latest release](https://github.com/cavaldos/Ice/releases/latest).
2. Unzip it and move `Ice.app` into `/Applications`.
3. Clear the quarantine flag — releases are ad-hoc signed and not notarized, so Gatekeeper would otherwise block the first launch:

```bash
xattr -d com.apple.quarantine /Applications/Ice.app
```

Then open Ice and grant **Accessibility** and **Screen Recording** in System Settings (see [Permissions](#permissions)).

For local development, see [script/README.md](script/README.md).

## Uninstall

**Homebrew:**

```bash
brew uninstall --cask cavaldos/tap/ice
```


```bash
brew uninstall --cask --zap cavaldos/tap/ice
```

**Manual:** quit Ice, then drag `Ice.app` out of `/Applications` to the Trash. To also remove preferences, delete `~/Library/Preferences/com.jordanbaird.Ice.plist`.


## Gallery

**Always-Hidden section demo — hide menu bar icons and reveal on hover**

![Demo of Ice always-hidden menu bar section on macOS](Resources/vid/demo-ah.gif)

**Show and hide menu bar icons demo**

![Demo showing and hiding Mac menu bar icons with Ice](Resources/vid/demo.gif)

**Fullscreen settings**

![Ice fullscreen settings window on macOS](Resources/Image/fullscreen.png)


| Ice Bar — second menu bar for notched MacBooks                                                   | Drag-and-drop menu bar layout                                                                   |
| ------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------- |
| ![Ice Bar second menu bar for MacBook notch](https://github.com/user-attachments/assets/f1429589-6186-4e1b-8aef-592219d49b9b) | ![Drag and drop menu bar layout editor](./Resources/Image/MenuBarLayout.png) |

| Menu bar appearance and theme settings                                                                  | Menu bar item spacing                                                                                       |
| ------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------- |
| ![Menu bar appearance theme settings](./Resources/Image/MenuBarAppearance.png) | ![Menu bar icon spacing settings](https://github.com/user-attachments/assets/b196aa7e-184a-4d4c-b040-502f4aae40a6) |


> ✅ **macOS 27 fully supported** — works on macOS 14 Sonoma and later, including Sequoia, Tahoe, and macOS 27. If you need a similar tool for macOS 13 Ventura or earlier, check out [Ice 0.11.x](https://github.com/jordanbaird/Ice/releases).


## Contributing

Contributions are welcome! Please read the [contribution guidelines](./Resources/document/CONTRIBUTING.md) before submitting a pull request.

## Contributors

Thanks to everyone who has contributed to this fork:

<a href="https://github.com/cavaldos"><img src="https://github.com/cavaldos.png?size=64" width="64" height="64" alt="cavaldos" title="cavaldos" style="border-radius:50%"></a>
<a href="https://github.com/pythongod"><img src="https://github.com/pythongod.png?size=64" width="64" height="64" alt="pythongod" title="pythongod" style="border-radius:50%"></a>
<a href="https://github.com/WuColin-1"><img src="https://github.com/WuColin-1.png?size=64" width="64" height="64" alt="WuColin-1" title="WuColin-1" style="border-radius:50%"></a>

## Support

<a href="https://ko-fi.com/calvados" target="_blank">
    <img src="https://storage.ko-fi.com/cdn/kofi5.png?v=6" alt="Support me on Ko-fi" style="height: 36px !important;width: 130px !important;">
</a>

<a href="https://www.paypal.com/paypalme/nnkhanh29" target="_blank">
    <img src="https://www.paypalobjects.com/webstatic/en_US/i/buttons/PP_logo_h_200x51.png" alt="Donate with PayPal" style="height: 36px !important;">
</a>

## Acknowledgments

A fork of [Ice](https://github.com/jordanbaird/Ice) by [Jordan Baird](https://github.com/jordanbaird) — huge thanks for the original work this project builds on.

## License

[GPL-3.0](LICENSE) — Ice is and will always remain open-source and free.

## Star History

<a href="https://star-history.com/#cavaldos/Ice&Date">
    <img src="https://api.star-history.com/svg?repos=cavaldos/Ice&type=Date" alt="Star History Chart" width="500">
</a>
