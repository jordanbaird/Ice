//
//  IceBar.swift
//  Ice
//

import Combine
import OSLog
import SwiftUI

// MARK: - IceBarPanel

final class IceBarPanel: NSPanel {
    /// The shared app state.
    private weak var appState: AppState?

    /// Manager for the Ice Bar's color.
    private let colorManager = IceBarColorManager()

    /// The currently displayed section.
    private(set) var currentSection: MenuBarSection.Name?

    /// Storage for internal observers.
    private var cancellables = Set<AnyCancellable>()

    /// A passive monitor that closes the panel when the user clicks in
    /// another app, used on macOS 27 where Ice installs no event taps.
    private var outsideClickMonitor: Any?

    /// Creates a new Ice Bar panel.
    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )
        self.title = "Ice Bar"
        self.titlebarAppearsTransparent = true
        self.isMovableByWindowBackground = true
        self.allowsToolTipsWhenApplicationIsInactive = true
        self.isFloatingPanel = true
        self.animationBehavior = .none
        self.backgroundColor = .clear
        self.hasShadow = false
        self.level = .mainMenu + 1
        self.collectionBehavior = [.fullScreenAuxiliary, .ignoresCycle, .moveToActiveSpace]
    }

    /// Sets up the panel.
    func performSetup(with appState: AppState) {
        self.appState = appState
        configureCancellables()
        colorManager.performSetup(with: self)
    }

    /// Configures the internal observers.
    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        // Hide the panel when the active space or screen parameters change.
        Publishers.Merge(
            NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.activeSpaceDidChangeNotification),
            NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
        )
        .sink { [weak self] _ in
            self?.hide()
        }
        .store(in: &c)

        // Update the panel's origin whenever its size changes.
        publisher(for: \.frame).map(\.size)
            .removeDuplicates()
            .sink { [weak self] _ in
                guard let self, let screen else {
                    return
                }
                updateOrigin(for: screen)
            }
            .store(in: &c)

        // On macOS 27, the hidden section's control item is never added to the
        // menu bar, so its missing frame says nothing about the menu bar.
        if #unavailable(macOS 27.0), let controlItem = appState?.menuBarManager.controlItem(withName: .hidden) {
            // Use the hidden control item's frame to determine if the menu bar
            // is hidden. Hide the panel if so.
            controlItem.$frame
                .combineLatest(controlItem.$screen)
                .throttle(for: 0.1, scheduler: DispatchQueue.main, latest: true)
                .sink { [weak self] (frame, screen) in
                    guard let self else {
                        return
                    }

                    guard let frame, let screen else {
                        hide()
                        return
                    }

                    // Icon is not vertically visible. We can infer that the
                    // menu bar is hidden.
                    if frame.maxY > screen.frame.maxY {
                        hide()
                    }
                }
                .store(in: &c)
        }

        cancellables = c
    }

    /// Updates the panel's frame origin for display on the given screen.
    private func updateOrigin(for screen: NSScreen) {
        guard let appState else {
            return
        }

        func getOrigin(for iceBarLocation: IceBarLocation) -> CGPoint {
            let menuBarHeight = screen.getMenuBarHeight()
                ?? max(screen.frame.maxY - screen.visibleFrame.maxY, NSStatusBar.system.thickness)
            let originY = ((screen.frame.maxY - 1) - menuBarHeight) - frame.height

            var originForRightOfScreen: CGPoint {
                CGPoint(x: screen.frame.maxX - frame.width, y: originY)
            }

            switch iceBarLocation {
            case .dynamic:
                if appState.hidEventManager.isMouseInsideEmptyMenuBarSpace(appState: appState, screen: screen) {
                    return getOrigin(for: .mousePointer)
                }
                return getOrigin(for: .iceIcon)
            case .mousePointer:
                guard let location = MouseHelpers.locationAppKit else {
                    return getOrigin(for: .iceIcon)
                }

                let lowerBound = screen.frame.minX
                let upperBound = screen.frame.maxX - frame.width

                guard lowerBound <= upperBound else {
                    return originForRightOfScreen
                }

                return CGPoint(x: (location.x - frame.width / 2).clamped(to: lowerBound...upperBound), y: originY)
            case .iceIcon:
                let lowerBound = screen.frame.minX
                let upperBound = screen.frame.maxX - frame.width

                if #available(macOS 27.0, *) {
                    guard
                        lowerBound <= upperBound,
                        let itemBounds = MacOS27MenuBarItemProvider.ownMenuBarItems()
                            .first(matching: .visibleControlItem)?.bounds
                    else {
                        return originForRightOfScreen
                    }
                    return CGPoint(x: (itemBounds.midX - frame.width / 2).clamped(to: lowerBound...upperBound), y: originY)
                }

                guard
                    lowerBound <= upperBound,
                    let controlItem = appState.itemManager.itemCache.managedItems.first(matching: .visibleControlItem),
                    // Bridging API is more reliable than controlItem.frame in some
                    // cases (like if the item is offscreen).
                    let itemBounds = Bridging.getWindowBounds(for: controlItem.windowID)
                else {
                    return originForRightOfScreen
                }

                return CGPoint(x: (itemBounds.midX - frame.width / 2).clamped(to: lowerBound...upperBound), y: originY)
            }
        }

        setFrameOrigin(getOrigin(for: appState.settings.general.iceBarLocation))
    }

    /// Shows the panel on the given screen, displaying the given
    /// menu bar section.
    func show(section: MenuBarSection.Name, on screen: NSScreen) async {
        guard let appState else {
            return
        }

        // IMPORTANT: We must set the navigation state and current section
        // before updating the caches.
        appState.navigationState.isIceBarPresented = true
        currentSection = section

        // On macOS 27, refreshing walks every running app's accessibility tree
        // and routinely hits the timeout, while concealed items can't be read or
        // captured anyway. Show the cached items at once; the periodic refresh
        // keeps them current.
        if #unavailable(macOS 27.0) {
            let cacheTask = Task(timeout: .seconds(1)) {
                await appState.itemManager.cacheItemsIfNeeded()
                await appState.imageCache.updateCache()
            }

            do {
                try await cacheTask.value
            } catch {
                Logger.default.error("Cache update failed when showing IceBarPanel - \(error)")
            }
        }

        contentView = IceBarHostingView(
            appState: appState,
            colorManager: colorManager,
            screen: screen,
            section: section
        )

        updateOrigin(for: screen)

        // Color manager must be updated after updating the panel's origin,
        // but before it is shown.
        //
        // Color manager handles frame changes automatically, but does so on
        // the main queue, so we need to update manually once before showing
        // the panel to prevent the color from flashing.
        colorManager.updateAllProperties(with: frame, screen: screen)

        orderFrontRegardless()

        if #available(macOS 27.0, *), outsideClickMonitor == nil {
            outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
            ) { [weak self] event in
                guard let self, isVisible, !frame.contains(NSEvent.mouseLocation) else {
                    return
                }
                // MenuBarAgent receives clicks on Ice's own button. Leave those
                // to the button's action, which closes the Ice Bar; closing it
                // here would make that action open it again.
                if
                    let location = event.cgEvent?.location ?? MouseHelpers.locationCoreGraphics,
                    let iceBounds = MacOS27MenuBarItemProvider.ownMenuBarItems()
                        .first(matching: .visibleControlItem)?.bounds,
                    iceBounds.insetBy(dx: -2, dy: -2).contains(location)
                {
                    return
                }
                hide()
            }
        }
    }

    /// Hides the panel.
    func hide() {
        if
            let name = currentSection,
            let section = appState?.menuBarManager.section(withName: name)
        {
            section.hide()
        }
        close()
    }

    override func close() {
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
            self.outsideClickMonitor = nil
        }
        super.close()
        contentView = nil
        currentSection = nil
        appState?.navigationState.isIceBarPresented = false
    }
}

// MARK: - IceBarHostingView

private final class IceBarHostingView: NSHostingView<IceBarContentView> {
    override var safeAreaInsets: NSEdgeInsets { NSEdgeInsets() }

    init(
        appState: AppState,
        colorManager: IceBarColorManager,
        screen: NSScreen,
        section: MenuBarSection.Name
    ) {
        let rootView = IceBarContentView(
            appState: appState,
            colorManager: colorManager,
            itemManager: appState.itemManager,
            imageCache: appState.imageCache,
            menuBarManager: appState.menuBarManager,
            screen: screen,
            section: section
        )
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @available(*, unavailable)
    required init(rootView: IceBarContentView) {
        fatalError("init(rootView:) has not been implemented")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }
}

// MARK: - IceBarContentView

private struct IceBarContentView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var colorManager: IceBarColorManager
    @ObservedObject var itemManager: MenuBarItemManager
    @ObservedObject var imageCache: MenuBarItemImageCache
    @ObservedObject var menuBarManager: MenuBarManager
    @State private var frame = CGRect.zero
    @State private var scrollIndicatorsFlashTrigger = 0

    let screen: NSScreen
    let section: MenuBarSection.Name

    private var items: [MenuBarItem] {
        itemManager.itemCache.managedItems(for: section)
    }

    /// Whether items without a captured image show their app's icon instead.
    /// Concealed items aren't drawn at all on macOS 27, so an image can be
    /// missing even with screen recording permission.
    private static var usesApplicationIconFallback: Bool {
        if #available(macOS 27.0, *) {
            return true
        }
        return false
    }

    private var configuration: MenuBarAppearanceConfigurationV2 {
        appState.appearanceManager.configuration
    }

    private var horizontalPadding: CGFloat {
        if #available(macOS 26.0, *) {
            return 3
        }
        return configuration.hasRoundedShape ? 7 : 5
    }

    private var verticalPadding: CGFloat {
        if #available(macOS 26.0, *) {
            return screen.hasNotch && configuration.hasRoundedShape ? 2 : 0
        }
        return screen.hasNotch ? 0 : 2
    }

    private var contentHeight: CGFloat? {
        guard let menuBarHeight = screen.getMenuBarHeight() else {
            return nil
        }
        if configuration.shapeKind != .noShape && configuration.isInset && screen.hasNotch {
            return menuBarHeight - appState.appearanceManager.menuBarInsetAmount * 2
        }
        return menuBarHeight
    }

    private var clipShape: some InsettableShape {
        if configuration.hasRoundedShape {
            RoundedRectangle(cornerRadius: frame.height / 2, style: .circular)
        } else if #available(macOS 26.0, *) {
            RoundedRectangle(cornerRadius: frame.height / 4, style: .continuous)
        } else {
            RoundedRectangle(cornerRadius: frame.height / 5, style: .continuous)
        }
    }

    private var backgroundOpacity: Double {
        appState.settings.general.iceBarBackgroundOpacity
    }

    private var shadowOpacity: CGFloat {
        configuration.current.hasShadow ? 0.5 : 0.33
    }

    /// The layer drawn between the Liquid Glass background and the items.
    ///
    /// Darkness chooses its shade, from white to black, and transparency
    /// chooses how much of the glass it covers: fully transparent leaves the
    /// bare glass, and opaque leaves a solid bar in that shade.
    private var glassTintFill: Color {
        let settings = appState.settings.general
        return Color(white: 1 - settings.iceBarGlassDarkness)
            .opacity(1 - settings.iceBarBackgroundTransparency)
    }

    var body: some View {
        if #available(macOS 26.0, *) {
            glassBody
        } else {
            menuBarStyleBody
        }
    }

    /// A dark Liquid Glass bar. Monochrome glyphs are templates, so they draw
    /// in the white foreground style.
    @available(macOS 26.0, *)
    private var glassBody: some View {
        content
            .frame(height: contentHeight)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .foregroundStyle(.white)
            .clipShape(clipShape)
            .background {
                clipShape.fill(glassTintFill)
            }
            .glassEffect(.regular, in: clipShape)
            .environment(\.colorScheme, .dark)
            .padding(5)
            .frame(maxWidth: screen.frame.width)
            .fixedSize()
            .onFrameChange(update: $frame)
    }

    private var menuBarStyleBody: some View {
        ZStack {
            content
                .frame(height: contentHeight)
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, verticalPadding)
                .menuBarItemContainer(
                    appState: appState,
                    colorInfo: colorManager.colorInfo,
                    backgroundOpacity: backgroundOpacity
                )
                .foregroundStyle(colorManager.colorInfo?.color.brightness ?? 0 > 0.67 ? .black : .white)
                .clipShape(clipShape)
                .shadow(color: .black.opacity(shadowOpacity * backgroundOpacity), radius: 2.5)

            if configuration.current.hasBorder {
                clipShape
                    .inset(by: configuration.current.borderWidth / 2)
                    .stroke(lineWidth: configuration.current.borderWidth)
                    .foregroundStyle(Color(cgColor: configuration.current.borderColor))
                    .opacity(backgroundOpacity)
            }
        }
        .padding(5)
        .frame(maxWidth: screen.frame.width)
        .fixedSize()
        .onFrameChange(update: $frame)
    }

    @ViewBuilder
    private var content: some View {
        if !Self.usesApplicationIconFallback, !ScreenCapture.cachedCheckPermissions() {
            HStack {
                Text("The Ice Bar requires screen recording permissions.")

                Button {
                    menuBarManager.section(withName: section)?.hide()
                    appState.navigationState.settingsNavigationIdentifier = .advanced
                    appState.activate(withPolicy: .regular)
                    appState.openWindow(.settings)
                } label: {
                    Text("Open Ice Settings")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.link)
            }
            .padding(.horizontal, 10)
        } else if menuBarManager.isMenuBarHiddenBySystemUserDefaults {
            Text("Ice cannot display menu bar items for automatically hidden menu bars")
                .padding(.horizontal, 10)
        } else if itemManager.itemCache.managedItems.isEmpty {
            HStack {
                Text("Loading menu bar items…")
                ProgressView()
                    .controlSize(.small)
            }
            .padding(.horizontal, 10)
        } else if !Self.usesApplicationIconFallback, imageCache.cacheFailed(for: section) {
            Text("Unable to display menu bar items")
                .padding(.horizontal, 10)
        } else {
            ScrollView(.horizontal) {
                HStack(spacing: appState.settings.general.iceBarItemSpacing) {
                    ForEach(items, id: \.windowID) { item in
                        IceBarItemView(
                            imageCache: imageCache,
                            itemManager: itemManager,
                            menuBarManager: menuBarManager,
                            item: item,
                            section: section
                        )
                    }
                }
            }
            .environment(\.isScrollEnabled, frame.width == screen.frame.width)
            .defaultScrollAnchor(.trailing)
            .scrollIndicatorsFlash(trigger: scrollIndicatorsFlashTrigger)
            .task {
                scrollIndicatorsFlashTrigger += 1
            }
        }
    }
}

// MARK: - IceBarItemView

private struct IceBarItemView: View {
    @ObservedObject var imageCache: MenuBarItemImageCache
    @ObservedObject var itemManager: MenuBarItemManager
    @ObservedObject var menuBarManager: MenuBarManager

    let item: MenuBarItem
    let section: MenuBarSection.Name

    private var leftClickAction: () -> Void {
        return { [weak itemManager, weak menuBarManager] in
            guard let itemManager, let menuBarManager else {
                return
            }
            menuBarManager.section(withName: section)?.hide()
            if #available(macOS 27.0, *) {
                Task {
                    await itemManager.clickConcealedItem(item, with: .left)
                }
                return
            }
            Task {
                try await Task.sleep(for: .milliseconds(25))
                if Bridging.isWindowOnScreen(item.windowID) {
                    try await itemManager.click(item: item, with: .left)
                } else {
                    await itemManager.temporarilyShow(item: item, clickingWith: .left)
                }
            }
        }
    }

    private var rightClickAction: () -> Void {
        return { [weak itemManager, weak menuBarManager] in
            guard let itemManager, let menuBarManager else {
                return
            }
            menuBarManager.section(withName: section)?.hide()
            if #available(macOS 27.0, *) {
                Task {
                    await itemManager.clickConcealedItem(item, with: .right)
                }
                return
            }
            Task {
                try await Task.sleep(for: .milliseconds(25))
                if Bridging.isWindowOnScreen(item.windowID) {
                    try await itemManager.click(item: item, with: .right)
                } else {
                    await itemManager.temporarilyShow(item: item, clickingWith: .right)
                }
            }
        }
    }

    private var image: NSImage? {
        if #available(macOS 27.0, *) {
            if
                let cachedImage = imageCache.images[item.tag],
                let glyph = IceBarGlyphImages.image(for: cachedImage, tag: item.tag)
            {
                return glyph
            }
            let items = itemManager.itemCache.managedItems
            let key = MacOS27SavedItemImages.key(for: item, among: items)
            if
                let savedImage = MacOS27SavedItemImages.image(forKey: key),
                let glyph = IceBarGlyphImages.image(for: savedImage, tag: item.tag)
            {
                return glyph
            }
            return applicationIcon
        }
        return imageCache.images[item.tag]?.nsImage
    }

    /// The icon of the app that owns the item, sized like a menu bar item.
    private var applicationIcon: NSImage? {
        guard
            let application = NSRunningApplication(processIdentifier: item.sourcePID ?? item.ownerPID),
            let icon = application.icon?.copy() as? NSImage
        else {
            return nil
        }
        icon.size = CGSize(width: 18, height: 18)
        let image = NSImage(size: CGSize(width: 28, height: 22), flipped: false) { bounds in
            icon.draw(in: CGRect(
                x: (bounds.width - icon.size.width) / 2,
                y: (bounds.height - icon.size.height) / 2,
                width: icon.size.width,
                height: icon.size.height
            ))
            return true
        }
        return image
    }

    var body: some View {
        if let image {
            Image(nsImage: image)
                .renderingMode(image.isTemplate ? .template : .original)
                .contentShape(Rectangle())
                .overlay {
                    IceBarItemClickView(
                        item: item,
                        leftClickAction: leftClickAction,
                        rightClickAction: rightClickAction
                    )
                }
                .accessibilityLabel(item.displayName)
                .accessibilityAction(named: "left click", leftClickAction)
                .accessibilityAction(named: "right click", rightClickAction)
        }
    }
}

// MARK: - IceBarGlyphImages

/// Converts captured menu bar crops into glyphs for the Ice Bar on macOS 27.
///
/// Other apps' status item images aren't available through any API, so the
/// crops come from a capture of the menu bar. Removing the bar's background
/// lets monochrome glyphs take the Ice Bar's foreground color, and colored
/// glyphs keep their colors on a transparent background.
@available(macOS 27.0, *)
@MainActor
private enum IceBarGlyphImages {
    private static let cache = NSCache<AnyObject, NSImage>()

    /// Returns the glyph for a capture, or `nil` when the menu bar background
    /// can't be separated from it. A raw crop is never returned: it would show
    /// a rectangle of wallpaper around the glyph.
    static func image(for capturedImage: MenuBarItemImageCache.CapturedImage, tag: MenuBarItemTag) -> NSImage? {
        let key = capturedImage.cgImage as AnyObject
        if let cached = cache.object(forKey: key) {
            return cached
        }
        let glyph = MenuBarGlyphImage.make(from: capturedImage.cgImage)
        guard let glyph, let trimmed = trimmedToVisiblePixels(glyph.image) else {
            if MacOS27GlyphDebug.isEnabled {
                MacOS27GlyphDebug.log("Ice Bar \(tag): no glyph extracted from \(capturedImage.cgImage.width)x\(capturedImage.cgImage.height)")
            }
            return nil
        }
        let image = centeredImage(trimmed, scale: capturedImage.scale)
        image.isTemplate = glyph.isTemplate
        if MacOS27GlyphDebug.isEnabled {
            MacOS27GlyphDebug.write(glyph.image, name: "\(tag)-glyph")
            MacOS27GlyphDebug.write(trimmed, name: "\(tag)-trimmed")
            let captureSize = "\(capturedImage.cgImage.width)x\(capturedImage.cgImage.height)"
            MacOS27GlyphDebug.log("Ice Bar \(tag): capture \(captureSize) at \(capturedImage.scale)x, template \(glyph.isTemplate), trimmed \(trimmed.width)x\(trimmed.height)")
        }
        cache.setObject(image, forKey: key)
        return image
    }

    /// Draws a glyph centered in a slot of uniform height. Apps report status
    /// item frames with different vertical offsets, so crops taken from those
    /// frames place their glyphs at different heights.
    private static func centeredImage(_ glyph: CGImage, scale: CGFloat) -> NSImage {
        let glyphSize = CGSize(
            width: CGFloat(glyph.width) / scale,
            height: CGFloat(glyph.height) / scale
        )
        let horizontalPadding: CGFloat = 7
        let slotSize = CGSize(
            width: glyphSize.width + horizontalPadding * 2,
            height: max(22, glyphSize.height)
        )
        return NSImage(size: slotSize, flipped: false) { bounds in
            guard let context = NSGraphicsContext.current?.cgContext else {
                return false
            }
            context.interpolationQuality = .high
            context.draw(glyph, in: CGRect(
                x: ((bounds.width - glyphSize.width) / 2).rounded(),
                y: ((bounds.height - glyphSize.height) / 2).rounded(),
                width: glyphSize.width,
                height: glyphSize.height
            ))
            return true
        }
    }

    /// Crops an image with transparency to the bounds of its visible pixels.
    private static func trimmedToVisiblePixels(_ image: CGImage) -> CGImage? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else {
            return nil
        }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(
                data: bytes.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                return false
            }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else {
            return nil
        }
        // Bitmap context rows run top to bottom, matching `cropping(to:)`.
        var minX = width
        var minY = height
        var maxX = -1
        var maxY = -1
        for y in 0 ..< height {
            for x in 0 ..< width where pixels[(y * width + x) * 4 + 3] > 12 {
                minX = min(minX, x)
                maxX = max(maxX, x)
                minY = min(minY, y)
                maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else {
            return nil
        }
        return image.cropping(to: CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1))
    }
}

// MARK: - IceBarItemClickView

private struct IceBarItemClickView: NSViewRepresentable {
    private final class Represented: NSView {
        let item: MenuBarItem

        let leftClickAction: () -> Void
        let rightClickAction: () -> Void

        private var lastLeftMouseDownDate = Date.now
        private var lastRightMouseDownDate = Date.now

        private var lastLeftMouseDownLocation = CGPoint.zero
        private var lastRightMouseDownLocation = CGPoint.zero

        init(
            item: MenuBarItem,
            leftClickAction: @escaping () -> Void,
            rightClickAction: @escaping () -> Void
        ) {
            self.item = item
            self.leftClickAction = leftClickAction
            self.rightClickAction = rightClickAction
            super.init(frame: .zero)
            self.toolTip = item.displayName
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func mouseDown(with event: NSEvent) {
            super.mouseDown(with: event)
            lastLeftMouseDownDate = .now
            lastLeftMouseDownLocation = NSEvent.mouseLocation
        }

        override func rightMouseDown(with event: NSEvent) {
            super.rightMouseDown(with: event)
            lastRightMouseDownDate = .now
            lastRightMouseDownLocation = NSEvent.mouseLocation
        }

        override func mouseUp(with event: NSEvent) {
            super.mouseUp(with: event)
            guard
                Date.now.timeIntervalSince(lastLeftMouseDownDate) < 0.5,
                lastLeftMouseDownLocation.distance(to: NSEvent.mouseLocation) < 5
            else {
                return
            }
            leftClickAction()
        }

        override func rightMouseUp(with event: NSEvent) {
            super.rightMouseUp(with: event)
            guard
                Date.now.timeIntervalSince(lastRightMouseDownDate) < 0.5,
                lastRightMouseDownLocation.distance(to: NSEvent.mouseLocation) < 5
            else {
                return
            }
            rightClickAction()
        }
    }

    let item: MenuBarItem

    let leftClickAction: () -> Void
    let rightClickAction: () -> Void

    func makeNSView(context: Context) -> NSView {
        Represented(
            item: item,
            leftClickAction: leftClickAction,
            rightClickAction: rightClickAction
        )
    }

    func updateNSView(_ nsView: NSView, context: Context) { }
}
