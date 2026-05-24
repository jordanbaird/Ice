//
//  LocalizationKey.swift
//  Ice
//

import Foundation

/// Keys for user-facing strings in the app.
///
/// Each case's raw value IS the English string (DRY).
enum LocalizationKey: String {
    // MARK: - General Settings

    case showIceIcon = "Show Ice icon"
    case iceIconSettings = "You can still access Ice's settings by right-clicking an empty area in the menu bar"
    case iceIcon = "Ice icon"
    case chooseImage = "Choose image..."
    case chooseCustomIcon = "Choose a custom icon to show in the menu bar"
    case applySystemTheme = "Apply system theme to icon"
    case applySystemThemeDetail = "Display the icon as a monochrome image matching the system appearance"
    case useIceBar = "Use Ice Bar"
    case useIceBarDetail = "Show hidden menu bar items in a separate bar below the menu bar"
    case location = "Location"
    case locationDynamic = "The Ice Bar's location changes based on context"
    case locationMousePointer = "The Ice Bar is centered below the mouse pointer"
    case locationIceIcon = "The Ice Bar is centered below the Ice icon"
    case showOnClick = "Show on click"
    case showOnClickDetail = "Click inside an empty area of the menu bar to show hidden menu bar items"
    case showOnHover = "Show on hover"
    case showOnHoverDetail = "Hover over an empty area of the menu bar to show hidden menu bar items"
    case showOnScroll = "Show on scroll"
    case showOnScrollDetail = "Scroll or swipe in the menu bar to toggle hidden menu bar items"
    case menuBarItemSpacing = "Menu bar item spacing"
    case apply = "Apply"
    case applySpacing = "Apply the current spacing"
    case resetToDefault = "Reset to the default spacing"
    case spacingRelaunchNote = "Applying this setting will relaunch all apps with menu bar items. Some apps may need to be manually relaunched."
    case spacingLogoutNote = "Note: You may need to log out and back in for this setting to apply properly."
    case autoRehide = "Automatically rehide"
    case strategy = "Strategy"
    case none_ = "none"
    case default_ = "default"
    case max = "max"
    case second = "second"
    case seconds = "seconds"

    // MARK: - Rehide Strategy

    case smart = "Smart"
    case timed = "Timed"
    case focusedApp = "Focused app"
    case smartDetail = "Menu bar items are rehidden using a smart algorithm"
    case timedDetail = "Menu bar items are rehidden after a fixed amount of time"
    case focusedAppDetail = "Menu bar items are rehidden when the focused app changes"

    // MARK: - Advanced Settings

    case permissions = "Permissions"
    case hideApplicationMenus = "Hide application menus when showing menu bar items"
    case hideApplicationMenusDetail = "Make more room in the menu bar by hiding the left application menus if needed"
    case showSectionDividers = "Show section dividers"
    case showSectionDividersDetailPrefix = "Insert divider items"
    case showSectionDividersDetailMiddle = "between sections"
    case enableAlwaysHiddenSection = "Enable always-hidden section"
    case canToggleAlwaysHiddenSection = "Always-hidden section can be shown"
    case toggleAlwaysHiddenSectionDetailWithOption = "Option + click one of Ice's menu bar items, or inside an empty area of the menu bar to show the section"
    case toggleAlwaysHiddenSectionDetail = "Option + click one of Ice's menu bar items to show the section"
    case showOnHoverDelay = "Show on hover delay"
    case showOnHoverDelayDetail = "The amount of time to wait before showing on hover"
    case tempShowInterval = "Temporarily shown item delay"
    case tempShowIntervalDetail = "The amount of time to wait before hiding temporarily shown menu bar items"
    case showAllSectionsOnUserDrag = "Show all sections when Command + dragging menu bar items"
    case showContextMenuOnRightClick = "Show context menu on right click"
    case permissionGranted = "Permission Granted"
    case grantPermission = "Grant Permission"
    case goToAdvancedSettings = "Go to Advanced Settings"
    case openIceSettings = "Open Ice Settings"

    // MARK: - Hotkeys Settings

    case menuBarSections = "Menu Bar Sections"
    case menuBarItems = "Menu Bar Items"
    case other = "Other"
    case toggleHiddenSection = "Toggle the hidden section"
    case toggleAlwaysHiddenSection = "Toggle the always-hidden section"
    case searchMenuBarItems = "Search menu bar items"
    case enableIceBar = "Enable the Ice Bar"
    case toggleSectionDividers = "Show section dividers (hotkey)"
    case toggleApplicationMenus = "Toggle application menus"

    // MARK: - Menu Bar Layout

    case dragToArrange = "Drag to arrange your menu bar items"
    case dragTip = "Tip: you can also arrange menu bar items by Command + dragging them in the menu bar"
    case layoutRequiresPermissions = "Menu bar layout requires screen recording permissions"
    case cannotArrangeInHiddenMenuBar = "Ice cannot arrange menu bar items in automatically hidden menu bars"
    case section = "Section"

    // MARK: - About

    case versionPrefix = "Version"
    case automaticallyCheckForUpdates = "Automatically check for updates"
    case automaticallyDownloadUpdates = "Automatically download updates"
    case checkForUpdates = "Check for Updates"
    case lastChecked = "Last checked:"
    case never = "Never"
    case quitIce = "Quit Ice"
    case acknowledgements = "Acknowledgements"
    case contribute = "Contribute"
    case reportABug = "Report a Bug"
    case supportIce = "Support Ice"

    // MARK: - Appearance

    case menuBarAppearance = "Menu Bar Appearance"
    case done = "Done"
    case useDynamicAppearance = "Use dynamic appearance"
    case useDynamicAppearanceDetail = "Apply different settings based on the current system appearance"
    case menuBarShape = "Menu Bar Shape"
    case appearanceTip = "Tip: you can also edit these settings by right-clicking in an empty area of the menu bar"
    case reset = "Reset"
    case cannotEditHiddenMenuBar = "Ice cannot edit the appearance of automatically hidden menu bars"
    case tint = "Tint"
    case shadow = "Shadow"
    case border = "Border"
    case borderColor = "Border Color"
    case borderWidth = "Border Width"
    case holdToPreview = "Hold to Preview"
    case useInsetShape = "Use inset shape on screens with notch"
    case shapeKind = "Shape Kind"
    case shapeNone = "None"
    case shapeFull = "Full"
    case shapeSplit = "Split"
    case noShapeSelected = "No shape kind selected"
    case squareCap = "Square Cap"
    case roundCap = "Round Cap"
    case leadingEndCap = "Leading End Cap"
    case trailingEndCap = "Trailing End Cap"
    case lightAppearance = "Light Appearance"
    case darkAppearance = "Dark Appearance"

    // MARK: - Section Names

    case visible = "Visible"
    case hidden = "Hidden"
    case alwaysHidden = "Always-Hidden"

    // MARK: - Ice Bar Location

    case dynamic = "Dynamic"
    case mousePointer = "Mouse pointer"

    // MARK: - Menu Bar Tint Kind

    case solid = "Solid"
    case gradient = "Gradient"

    // MARK: - App Language

    case language = "Language"
    case systemLanguage = "System"
    case english = "English"
    case chinese = "中文"
    case languageAnnotation = "Choose between English and Chinese, or automatically detect from system settings"

    // MARK: - NSMenu Items

    case iceSettings = "Ice Settings…"
    case searchMenuBarItemsMenu = "Search Menu Bar Items"
    case showSection = "Show the"
    case hideSection = "Hide the"
    case checkForUpdatesMenu = "Check for Updates…"
    case editMenuBarAppearance = "Edit Menu Bar Appearance…"

    // MARK: - Ice Bar Panel

    case iceBarPanelTitle = "Ice Bar"
    case iceBarRequiresPermissions = "The Ice Bar requires screen recording permissions."
    case iceBarCannotDisplay = "Ice cannot display menu bar items for automatically hidden menu bars"
    case unableToDisplayItems = "Unable to display menu bar items"
    case leftClick = "left click"
    case rightClick = "right click"

    // MARK: - General UI

    case quit = "Quit"
    case continue_ = "Continue"
    case continueInLimitedMode = "Continue in Limited Mode"

    // MARK: - Permissions

    case iceNeedsPermission = "Ice needs permission to manage the menu bar."
    case noPersonalInfo = "Absolutely no personal information is collected or stored."
    case needsThisTo = "Ice needs this to:"
    case limitedModeNote = "Ice can work in a limited mode without this permission."
    case accessibility = "Accessibility"
    case accessibilityDetail1 = "Get real-time information about the menu bar."
    case accessibilityDetail2 = "Arrange menu bar items."
    case screenRecording = "Screen Recording"
    case screenRecordingDetail1 = "Edit the menu bar's appearance."
    case screenRecordingDetail2 = "Display images of individual menu bar items."

    // MARK: - Search Panel

    case searchPlaceholder = "Search menu bar items…"
    case clickItem = "Click item"
    case showItem = "Show item"

    // MARK: - Alerts

    case hotkeyReserved = "Hotkey is reserved by macOS"
    case recordHotkey = "Record Hotkey"
    case typeHotkey = "Type Hotkey"
    case errorText = "ERROR"
    case ok = "OK"
    case itemNotMovable = "Menu bar item is not movable."
    case debugModeMessage = "Checking for updates is not supported in debug mode."
    case migrationMessage = "Due to a bug in the 0.10.0 release, the data for Ice's menu bar items was corrupted and their positions had to be reset."
    case migrationApology = "Our sincerest apologies for the inconvenience."
    case updateAvailable = "A new update is available"
    case versionAvailable = "is now available"
    case notEnoughRoom = "Not enough room to show"

    // MARK: - Settings Navigation

    case general = "General"
    case settingsMenuBarLayout = "Menu Bar Layout"
    case settingsMenuBarAppearance = "Menu Bar Appearance (settings)"
    case settingsHotkeys = "Hotkeys"
    case advanced = "Advanced"
    case about = "About"

    // MARK: - Beta

    case beta = "BETA"
}

extension LocalizationKey {
    var chinese: String {
        switch self {
        // General Settings
        case .showIceIcon: return "显示 Ice 图标"
        case .iceIconSettings: return "你仍然可以通过右键点击菜单栏空白区域来访问 Ice 的设置"
        case .iceIcon: return "Ice 图标"
        case .chooseImage: return "选择图片…"
        case .chooseCustomIcon: return "选择要显示在菜单栏中的自定义图标"
        case .applySystemTheme: return "图标跟随系统主题"
        case .applySystemThemeDetail: return "以单色图像显示图标，匹配系统外观"
        case .useIceBar: return "使用 Ice Bar"
        case .useIceBarDetail: return "在菜单栏下方显示一个单独的栏，展示隐藏的菜单栏项目"
        case .location: return "位置"
        case .locationDynamic: return "Ice Bar 的位置会根据上下文变化"
        case .locationMousePointer: return "Ice Bar 显示在鼠标指针下方居中"
        case .locationIceIcon: return "Ice Bar 显示在 Ice 图标下方居中"
        case .showOnClick: return "点击显示"
        case .showOnClickDetail: return "点击菜单栏空白区域以显示隐藏的菜单栏项目"
        case .showOnHover: return "悬停显示"
        case .showOnHoverDetail: return "悬停在菜单栏空白区域以显示隐藏的菜单栏项目"
        case .showOnScroll: return "滚动显示"
        case .showOnScrollDetail: return "在菜单栏中滚动或轻扫以切换隐藏的菜单栏项目"
        case .menuBarItemSpacing: return "菜单栏项目间距"
        case .apply: return "应用"
        case .applySpacing: return "应用当前间距"
        case .resetToDefault: return "重置为默认间距"
        case .spacingRelaunchNote: return "应用此设置将重新启动所有带有菜单栏项目的应用。某些应用可能需要手动重新启动。"
        case .spacingLogoutNote: return "注意：你可能需要注销后重新登录才能让此设置正确生效。"
        case .autoRehide: return "自动重新隐藏"
        case .strategy: return "策略"
        case .none_: return "无"
        case .default_: return "默认"
        case .max: return "最大"
        case .second: return "秒"
        case .seconds: return "秒"

        // Rehide Strategy
        case .smart: return "智能"
        case .timed: return "定时"
        case .focusedApp: return "切换应用时"
        case .smartDetail: return "使用智能算法重新隐藏菜单栏项目"
        case .timedDetail: return "在固定时间后重新隐藏菜单栏项目"
        case .focusedAppDetail: return "当最前面的应用改变时重新隐藏菜单栏项目"

        // Advanced
        case .permissions: return "权限"
        case .hideApplicationMenus: return "显示菜单栏项目时隐藏应用程序菜单"
        case .hideApplicationMenusDetail: return "在需要时隐藏左侧的应用程序菜单以腾出更多空间"
        case .showSectionDividers: return "显示分区分隔符"
        case .showSectionDividersDetailPrefix: return "在各个分区之间"
        case .showSectionDividersDetailMiddle: return "插入分隔项目"
        case .enableAlwaysHiddenSection: return "启用始终隐藏分区"
        case .canToggleAlwaysHiddenSection: return "可切换始终隐藏分区"
        case .toggleAlwaysHiddenSectionDetailWithOption: return "Option + 点击 Ice 的菜单栏项目，或点击菜单栏空白区域以显示该分区"
        case .toggleAlwaysHiddenSectionDetail: return "Option + 点击 Ice 的菜单栏项目以显示该分区"
        case .showOnHoverDelay: return "悬停显示延迟"
        case .showOnHoverDelayDetail: return "悬停后等待多长时间再显示"
        case .tempShowInterval: return "临时显示项目延迟"
        case .tempShowIntervalDetail: return "等待多长时间后隐藏临时显示的菜单栏项目"
        case .showAllSectionsOnUserDrag: return "按住 Command 拖拽菜单栏项目时显示所有分区"
        case .showContextMenuOnRightClick: return "右键点击时显示上下文菜单"
        case .permissionGranted: return "权限已授予"
        case .grantPermission: return "授予权限"
        case .goToAdvancedSettings: return "前往高级设置"
        case .openIceSettings: return "打开 Ice 设置"

        // Hotkeys
        case .menuBarSections: return "菜单栏分区"
        case .menuBarItems: return "菜单栏项目"
        case .other: return "其他"
        case .toggleHiddenSection: return "切换隐藏分区"
        case .toggleAlwaysHiddenSection: return "切换始终隐藏分区"
        case .searchMenuBarItems: return "搜索菜单栏项目"
        case .enableIceBar: return "启用 Ice Bar"
        case .toggleSectionDividers: return "显示分区分隔符"
        case .toggleApplicationMenus: return "切换应用程序菜单"

        // Layout
        case .dragToArrange: return "拖拽以排列你的菜单栏项目"
        case .dragTip: return "提示：你也可以在菜单栏中按住 Command 拖拽来排列菜单栏项目"
        case .layoutRequiresPermissions: return "菜单栏布局需要屏幕录制权限"
        case .cannotArrangeInHiddenMenuBar: return "Ice 无法在自动隐藏的菜单栏中排列菜单栏项目"
        case .section: return "分区"

        // About
        case .versionPrefix: return "版本"
        case .automaticallyCheckForUpdates: return "自动检查更新"
        case .automaticallyDownloadUpdates: return "自动下载更新"
        case .checkForUpdates: return "检查更新"
        case .lastChecked: return "上次检查："
        case .never: return "从未"
        case .quitIce: return "退出 Ice"
        case .acknowledgements: return "致谢"
        case .contribute: return "贡献"
        case .reportABug: return "报告错误"
        case .supportIce: return "支持 Ice"

        // Appearance
        case .menuBarAppearance: return "菜单栏外观"
        case .done: return "完成"
        case .useDynamicAppearance: return "使用动态外观"
        case .useDynamicAppearanceDetail: return "根据当前系统外观应用不同的设置"
        case .menuBarShape: return "菜单栏形状"
        case .appearanceTip: return "提示：你也可以通过右键点击菜单栏空白区域来编辑这些设置"
        case .reset: return "重置"
        case .cannotEditHiddenMenuBar: return "Ice 无法编辑自动隐藏的菜单栏的外观"
        case .tint: return "色调"
        case .shadow: return "阴影"
        case .border: return "边框"
        case .borderColor: return "边框颜色"
        case .borderWidth: return "边框宽度"
        case .holdToPreview: return "按住预览"
        case .useInsetShape: return "在带刘海的屏幕上使用内嵌形状"
        case .shapeKind: return "形状类型"
        case .shapeNone: return "无"
        case .shapeFull: return "完整"
        case .shapeSplit: return "分割"
        case .noShapeSelected: return "未选择形状"
        case .squareCap: return "方头端帽"
        case .roundCap: return "圆头端帽"
        case .leadingEndCap: return "前导端帽"
        case .trailingEndCap: return "尾部端帽"
        case .lightAppearance: return "浅色外观"
        case .darkAppearance: return "深色外观"

        // Section Names
        case .visible: return "可见"
        case .hidden: return "隐藏"
        case .alwaysHidden: return "始终隐藏"

        // Ice Bar Location
        case .dynamic: return "动态"
        case .mousePointer: return "鼠标指针"

        // Tint Kind
        case .solid: return "纯色"
        case .gradient: return "渐变"

        // Language
        case .language: return "语言"
        case .systemLanguage: return "系统"
        case .english: return "English"
        case .chinese: return "中文"
        case .languageAnnotation: return "选择英语或中文界面，或自动跟随系统设置"

        // NSMenu
        case .iceSettings: return "Ice 设置…"
        case .searchMenuBarItemsMenu: return "搜索菜单栏项目"
        case .showSection: return "显示"
        case .hideSection: return "隐藏"
        case .checkForUpdatesMenu: return "检查更新…"
        case .editMenuBarAppearance: return "编辑菜单栏外观…"

        // Ice Bar
        case .iceBarPanelTitle: return "Ice Bar"
        case .iceBarRequiresPermissions: return "Ice Bar 需要屏幕录制权限。"
        case .iceBarCannotDisplay: return "Ice 无法在自动隐藏的菜单栏中显示菜单栏项目"
        case .unableToDisplayItems: return "无法显示菜单栏项目"
        case .leftClick: return "左键点击"
        case .rightClick: return "右键点击"

        // General UI
        case .quit: return "退出"
        case .continue_: return "继续"
        case .continueInLimitedMode: return "以受限模式继续"

        // Permissions
        case .iceNeedsPermission: return "Ice 需要权限来管理菜单栏。"
        case .noPersonalInfo: return "绝对不会收集或存储任何个人信息。"
        case .needsThisTo: return "Ice 需要此权限来："
        case .limitedModeNote: return "没有此权限时，Ice 可以在受限模式下运行。"
        case .accessibility: return "辅助功能"
        case .accessibilityDetail1: return "实时获取菜单栏信息。"
        case .accessibilityDetail2: return "排列菜单栏项目。"
        case .screenRecording: return "屏幕录制"
        case .screenRecordingDetail1: return "编辑菜单栏的外观。"
        case .screenRecordingDetail2: return "显示各个菜单栏项目的图像。"

        // Search
        case .searchPlaceholder: return "搜索菜单栏项目…"
        case .clickItem: return "点击项目"
        case .showItem: return "显示项目"

        // Alerts
        case .hotkeyReserved: return "此快捷键已被 macOS 保留"
        case .recordHotkey: return "录制快捷键"
        case .typeHotkey: return "输入快捷键"
        case .errorText: return "错误"
        case .ok: return "确定"
        case .itemNotMovable: return "菜单栏项目无法移动。"
        case .debugModeMessage: return "调试模式下不支持检查更新。"
        case .migrationMessage: return "由于 0.10.0 版本中的一个错误，Ice 的菜单栏项目数据已损坏，其位置已被重置。"
        case .migrationApology: return "对于造成的不便，我们深表歉意。"
        case .updateAvailable: return "有新版本可用"
        case .versionAvailable: return "现已可用"
        case .notEnoughRoom: return "没有足够的空间来显示"

        // Settings Navigation
        case .general: return "通用"
        case .settingsMenuBarLayout: return "菜单栏布局"
        case .settingsMenuBarAppearance: return "菜单栏外观"
        case .settingsHotkeys: return "快捷键"
        case .advanced: return "高级"
        case .about: return "关于"

        // Beta
        case .beta: return "测试版"
        }
    }
}
