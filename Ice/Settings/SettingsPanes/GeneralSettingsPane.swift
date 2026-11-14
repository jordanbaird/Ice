//
//  GeneralSettingsPane.swift
//  Ice
//

import LaunchAtLogin
import SwiftUI

struct GeneralSettingsPane: View {
    @EnvironmentObject var appState: AppState
    @State private var isImportingCustomIceIcon = false
    @State private var isPresentingError = false
    @State private var presentedError: LocalizedErrorWrapper?
    @State private var isApplyingOffset = false
    @State private var isPresentingLogoutPrompt = false
    @State private var tempItemSpacingOffset: CGFloat = 0 // Temporary state for the slider

    private var manager: GeneralSettingsManager {
        appState.settingsManager.generalSettingsManager
    }

    private var itemSpacingOffset: LocalizedStringKey {
        localizedOffsetString(for: manager.itemSpacingOffset)
    }

    private func localizedOffsetString(for offset: CGFloat) -> LocalizedStringKey {
        switch offset {
        case -16:
            return LocalizedStringKey("none")
        case 0:
            return LocalizedStringKey("default")
        case 16:
            return LocalizedStringKey("max")
        default:
            return LocalizedStringKey(offset.formatted())
        }
    }

    private var rehideIntervalKey: LocalizedStringKey {
        let formatted = manager.rehideInterval.formatted()
        if manager.rehideInterval == 1 {
            return LocalizedStringKey(formatted + " second")
        } else {
            return LocalizedStringKey(formatted + " seconds")
        }
    }

    private var hasSpacingSliderValueChanged: Bool {
        tempItemSpacingOffset != manager.itemSpacingOffset
    }

    private var isActualOffsetDifferentFromDefault: Bool {
        manager.itemSpacingOffset != 0
    }

    /// Rightmost menu bar icons for the spacing demo, deduplicated by app.
    private var previewIcons: [MenuBarSpacingPreview.PreviewIcon] {
        let ownBundleID = Bundle.main.bundleIdentifier
        var seen = Set<String>()
        let images = appState.itemManager.itemCache.allItems
            .filter { $0.owningApplication?.bundleIdentifier != ownBundleID }
            .sorted { $0.frame.minX < $1.frame.minX }
            .compactMap { item -> NSImage? in
                guard
                    let app = item.owningApplication,
                    let icon = app.icon
                else {
                    return nil
                }
                let key = app.bundleIdentifier ?? item.displayName
                guard seen.insert(key).inserted else {
                    return nil
                }
                return icon
            }
            .suffix(8)
        let icons = images.map { MenuBarSpacingPreview.PreviewIcon.image($0) }
        return icons.isEmpty ? MenuBarSpacingPreview.fallbackIcons : Array(icons)
    }

    /// Average menu bar color for the demo background, when known.
    private var previewBarColor: Color? {
        guard let cgColor = appState.menuBarManager.averageColorInfo?.color else {
            return nil
        }
        return Color(cgColor: cgColor)
    }

    var body: some View {
        IceForm {
            IceSection {
                launchAtLogin
            }
            IceSection {
                iceIconOptions
            }
            IceSection {
                iceBarOptions
            }
            IceSection {
                showOnClick
                showOnHover
                showOnScroll
            }
            IceSection {
                autoRehideOptions
            }
            IceSection {
                spacingOptions
            }
        }
        .alert(isPresented: $isPresentingError, error: presentedError) {
            Button("OK") {
                presentedError = nil
                isPresentingError = false
            }
        }
        .alert("Spacing saved", isPresented: $isPresentingLogoutPrompt) {
            Button("Log Out Now") {
                logOut()
            }
            Button("Later", role: .cancel) { }
        } message: {
            Text("Menu bar spacing takes effect after you log out and back in.")
        }
    }

    @ViewBuilder
    private var launchAtLogin: some View {
        LaunchAtLogin.Toggle()
    }

    @ViewBuilder
    private func menuItem(for imageSet: ControlItemImageSet) -> some View {
        Label {
            Text(imageSet.name.rawValue)
        } icon: {
            let image = manager.reverseIceIcon ? imageSet.hidden : imageSet.visible
            if let nsImage = image.nsImage(for: appState) {
                switch imageSet.name {
                case .custom:
                    Image(size: CGSize(width: 18, height: 18)) { context in
                        context.draw(
                            Image(nsImage: nsImage),
                            in: context.clipBoundingRect
                        )
                    }
                default:
                    Image(nsImage: nsImage)
                }
            }
        }
    }

    @ViewBuilder
    private var iceIconOptions: some View {
        Toggle("Show Ice icon", isOn: manager.bindings.showIceIcon)
            .annotation {
                if !manager.showIceIcon {
                    Text("You can still access Ice's settings by right-clicking an empty area in the menu bar")
                }
            }
        if manager.showIceIcon {
            IceMenu("Ice icon") {
                Picker("Ice icon", selection: manager.bindings.iceIcon) {
                    ForEach(ControlItemImageSet.userSelectableIceIcons) { imageSet in
                        Button {
                            manager.iceIcon = imageSet
                        } label: {
                            menuItem(for: imageSet)
                        }
                        .tag(imageSet)
                    }
                    if let lastCustomIceIcon = manager.lastCustomIceIcon {
                        Button {
                            manager.iceIcon = lastCustomIceIcon
                        } label: {
                            menuItem(for: lastCustomIceIcon)
                        }
                        .tag(lastCustomIceIcon)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()

                Button("Choose image…") {
                    isImportingCustomIceIcon = true
                }
            } title: {
                menuItem(for: manager.iceIcon)
            }
            .annotation("Choose a custom icon to show in the menu bar")
            .fileImporter(
                isPresented: $isImportingCustomIceIcon,
                allowedContentTypes: [.image]
            ) { result in
                do {
                    let url = try result.get()
                    if url.startAccessingSecurityScopedResource() {
                        defer { url.stopAccessingSecurityScopedResource() }
                        let data = try Data(contentsOf: url)
                        manager.iceIcon = ControlItemImageSet(name: .custom, image: .data(data))
                    }
                } catch {
                    presentedError = LocalizedErrorWrapper(error)
                    isPresentingError = true
                }
            }

            Toggle("Reverse Ice icon", isOn: manager.bindings.reverseIceIcon)
                .annotation("Point the arrow the opposite way when hidden")

            if case .custom = manager.iceIcon.name {
                Toggle("Apply system theme to icon", isOn: manager.bindings.customIceIconIsTemplate)
                    .annotation("Display the icon as a monochrome image matching the system appearance")
            }
        }
    }

    @ViewBuilder
    private var iceBarOptions: some View {
        useIceBar
        if manager.useIceBar {
            iceBarLocationPicker
        }
    }

    @ViewBuilder
    private var useIceBar: some View {
        Toggle(isOn: manager.bindings.useIceBar) {
            HStack {
                Text("Use Ice Bar")
                BetaBadge()
            }
        }
            .annotation("Show hidden menu bar items in a separate bar below the menu bar")
    }

    @ViewBuilder
    private var iceBarLocationPicker: some View {
        IcePicker("Location", selection: manager.bindings.iceBarLocation) {
            ForEach(IceBarLocation.allCases) { location in
                Text(location.localized).tag(location)
            }
        }
        .annotation {
            switch manager.iceBarLocation {
            case .dynamic:
                Text("The Ice Bar's location changes based on context")
            case .mousePointer:
                Text("The Ice Bar is centered below the mouse pointer")
            case .iceIcon:
                Text("The Ice Bar is centered below the Ice icon")
            }
        }
    }

    @ViewBuilder
    private var showOnClick: some View {
        Toggle("Show on click", isOn: manager.bindings.showOnClick)
            .annotation("Click inside an empty area of the menu bar to show hidden menu bar items")
    }

    @ViewBuilder
    private var showOnHover: some View {
        Toggle("Show on hover", isOn: manager.bindings.showOnHover)
            .annotation("Hover over an empty area of the menu bar to show hidden menu bar items")
    }

    @ViewBuilder
    private var showOnScroll: some View {
        Toggle("Show on scroll", isOn: manager.bindings.showOnScroll)
            .annotation("Scroll or swipe in the menu bar to toggle hidden menu bar items")
    }

    @ViewBuilder
    private var spacingOptions: some View {
        VStack(alignment: .leading, spacing: 8) {
            MenuBarSpacingPreview(
                icons: previewIcons,
                spacing: 16 + tempItemSpacingOffset,
                barColor: previewBarColor
            )
            IceLabeledContent {
                IceSlider(
                    localizedOffsetString(for: tempItemSpacingOffset),
                    value: $tempItemSpacingOffset,
                    in: -16...16,
                    step: 2
                )
                .disabled(isApplyingOffset)
            } label: {
                IceLabeledContent {
                    Button("Apply") {
                        applyOffset()
                    }
                    .help("Apply the current spacing")
                    .disabled(isApplyingOffset || !hasSpacingSliderValueChanged)

                    if isApplyingOffset {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .scaleEffect(0.5)
                            .frame(width: 15, height: 15)
                    } else {
                        Button {
                            resetOffsetToDefault()
                        } label: {
                            Image(systemName: "arrow.counterclockwise.circle.fill")
                        }
                        .buttonStyle(.borderless)
                        .help("Reset to the default spacing")
                        .disabled(isApplyingOffset || !isActualOffsetDifferentFromDefault)
                    }
                } label: {
                    Text("Menu bar item spacing")
                }
            }
        }
        .annotation(
            MenuBarItemSpacingManager.requiresLogoutToApply
                ? "Applying this setting saves the new spacing. Nothing restarts — log out and back in to see it."
                : "Applying this setting will relaunch all apps with menu bar items. Some apps may need to be manually relaunched.",
            spacing: 2
        )
        .annotation(spacing: 10, font: .callout.bold()) {
            IceGroupBox {
                Label {
                    Text(
                        MenuBarItemSpacingManager.requiresLogoutToApply
                            ? "Note: On this macOS version, menu bar spacing only takes effect after you log out and back in."
                            : "Note: You may need to log out and back in for this setting to apply properly."
                    )
                } icon: {
                    Image(systemName: "exclamationmark.circle")
                }
                .frame(maxWidth: .infinity)
            }
        }
        .onAppear {
            tempItemSpacingOffset = manager.itemSpacingOffset
        }
        .onChange(of: manager.itemSpacingOffset) { _, newValue in
            // Keep the slider in sync if the offset changes elsewhere.
            if !isApplyingOffset {
                tempItemSpacingOffset = newValue
            }
        }
    }

    @ViewBuilder
    private var rehideStrategyPicker: some View {
        IcePicker("Strategy", selection: manager.bindings.rehideStrategy) {
            ForEach(RehideStrategy.allCases) { strategy in
                Text(strategy.localized).tag(strategy)
            }
        }
        .annotation {
            switch manager.rehideStrategy {
            case .smart:
                Text("Menu bar items are rehidden using a smart algorithm")
            case .timed:
                Text("Menu bar items are rehidden after a fixed amount of time")
            case .focusedApp:
                Text("Menu bar items are rehidden when the focused app changes")
            }
        }
    }

    @ViewBuilder
    private var autoRehideOptions: some View {
        Toggle("Automatically rehide", isOn: manager.bindings.autoRehide)
        if manager.autoRehide {
            if case .timed = manager.rehideStrategy {
                VStack {
                    rehideStrategyPicker
                    IceSlider(
                        rehideIntervalKey,
                        value: manager.bindings.rehideInterval,
                        in: 0...30,
                        step: 1
                    )
                }
            } else {
                rehideStrategyPicker
            }
        }
    }

    /// Apply menu bar spacing offset.
    private func applyOffset() {
        isApplyingOffset = true
        let previousOffset = manager.itemSpacingOffset
        let newOffset = tempItemSpacingOffset
        manager.itemSpacingOffset = newOffset
        // Sync synchronously: the Combine sink that mirrors this value onto
        // spacingManager.offset runs async, so without this line the Task
        // below can read (and write to the system) a stale offset while the
        // UI already shows the new one — Apply then looks "broken".
        appState.spacingManager.offset = Int(newOffset)
        Task {
            do {
                try await appState.spacingManager.applyOffset()
                // macOS 26+: prefs are login-time only, so offer logout right away.
                if MenuBarItemSpacingManager.requiresLogoutToApply {
                    isPresentingLogoutPrompt = true
                }
            } catch {
                // Relaunch failed but `defaults write` already succeeded, so keep
                // the new value (it matches the system). Only revert when the
                // defaults write itself failed.
                if error is MenuBarItemSpacingManager.GroupedRelaunchError {
                    tempItemSpacingOffset = newOffset
                } else {
                    manager.itemSpacingOffset = previousOffset
                    tempItemSpacingOffset = previousOffset
                }
                let alert = NSAlert(error: error)
                alert.runModal()
            }
            isApplyingOffset = false
        }
    }

    /// Ask the system to log out (shows the standard confirmation dialog).
    private func logOut() {
        // ponytail: osascript instead of NSAppleScript/ScriptingBridge — no new
        // entitlement, no API to maintain; confirmation dialog keeps it safe.
        Task.detached {
            let process = Process()
            process.executableURL = URL(filePath: "/usr/bin/osascript")
            process.arguments = ["-e", "tell application \"System Events\" to log out"]
            try? process.run()
            process.waitUntilExit()
        }
    }

    /// Reset menu bar spacing offset to default.
    private func resetOffsetToDefault() {
        tempItemSpacingOffset = 0
        applyOffset()
    }
}
