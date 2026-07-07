//
//  ScreenShapePicker.swift
//  Ice
//

import SwiftUI

struct ScreenShapePicker: View {
    @EnvironmentObject var appearanceManager: MenuBarAppearanceManager

    @State private var selectedScreenIdentifier: String?
    @State private var screens: [NSScreen] = NSScreen.screens

    private var selectedInfo: ScreenShapeInfo {
        if let id = selectedScreenIdentifier,
           let override = appearanceManager.configuration.screenShapeOverrides[id] {
            return override
        }
        return appearanceManager.configuration.screenShapeInfo
    }

    private var isUsingDefaults: Bool {
        guard let id = selectedScreenIdentifier else {
            return appearanceManager.configuration.screenShapeInfo == .default
        }
        guard let override = appearanceManager.configuration.screenShapeOverrides[id] else {
            return true
        }
        return override == appearanceManager.configuration.screenShapeInfo
    }

    private func setSelectedInfo(_ info: ScreenShapeInfo) {
        var config = appearanceManager.configuration
        if let id = selectedScreenIdentifier {
            if info == config.screenShapeInfo {
                config.screenShapeOverrides.removeValue(forKey: id)
            } else {
                config.screenShapeOverrides[id] = info
            }
        } else {
            let oldDefaultInfo = config.screenShapeInfo
            config.screenShapeInfo = info
            removeRedundantScreenShapeOverrides(
                from: &config,
                matching: [oldDefaultInfo, info]
            )
        }
        appearanceManager.configuration = config
    }

    private func removeRedundantScreenShapeOverrides(
        from config: inout MenuBarAppearanceConfigurationV2,
        matching defaultInfos: [ScreenShapeInfo]
    ) {
        let defaults = Set(defaultInfos)
        config.screenShapeOverrides = config.screenShapeOverrides.filter { _, info in
            !defaults.contains(info)
        }
    }

    private func bindingFor<Value>(_ keyPath: WritableKeyPath<ScreenShapeInfo, Value>) -> Binding<Value> {
        Binding(
            get: { selectedInfo[keyPath: keyPath] },
            set: { newValue in
                var info = selectedInfo
                info[keyPath: keyPath] = newValue
                setSelectedInfo(info)
            }
        )
    }

    private var topCornersBinding: Binding<Bool> {
        Binding(
            get: { selectedInfo.hasRoundedTopCorners },
            set: { newValue in
                var info = selectedInfo
                info.hasRoundedTopCorners = newValue
                setSelectedInfo(info)
            }
        )
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            togglesColumn
            Spacer(minLength: 8)
            preview
            Spacer(minLength: 8)
            settingsColumn
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            screens = NSScreen.screens
            if let id = selectedScreenIdentifier,
               !screens.contains(where: { $0.stableIdentifier == id }) {
                selectedScreenIdentifier = nil
            }
        }
        .onAppear(perform: removeRedundantScreenShapeOverrides)
    }

    // MARK: Toggles column

    @ViewBuilder
    private var togglesColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            topPicker
            bottomPicker
        }
    }

    @ViewBuilder
    private var topPicker: some View {
        Picker("Top Corners", selection: topCornersBinding) {
            cornerIcon(rounded: false, edge: .top).tag(false)
            cornerIcon(rounded: true, edge: .top).tag(true)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
        .help("Rounded screen top corners")
    }

    @ViewBuilder
    private var bottomPicker: some View {
        Picker("Bottom Corners", selection: bindingFor(\.hasRoundedBottomCorners)) {
            cornerIcon(rounded: false, edge: .bottom).tag(false)
            cornerIcon(rounded: true, edge: .bottom).tag(true)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
        .help("Rounded screen bottom corners")
    }

    @ViewBuilder
    private func cornerIcon(rounded: Bool, edge: VerticalEdge) -> some View {
        Image(size: CGSize(width: 16, height: 12)) { context in
            let radius: CGFloat = rounded ? 5 : 0
            let shape: UnevenRoundedRectangle
            switch edge {
            case .top:
                shape = UnevenRoundedRectangle(
                    topLeadingRadius: radius,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: radius,
                    style: .continuous
                )
            case .bottom:
                shape = UnevenRoundedRectangle(
                    topLeadingRadius: 0,
                    bottomLeadingRadius: radius,
                    bottomTrailingRadius: radius,
                    topTrailingRadius: 0,
                    style: .continuous
                )
            }
            context.fill(shape.path(in: context.clipBoundingRect), with: .foreground)
        }
        .resizable()
    }

    // MARK: Preview

    @ViewBuilder
    private var preview: some View {
        let scaled = min(selectedInfo.cornerRadius * 0.3, 22)
        let topRadius: CGFloat = selectedInfo.hasRoundedTopCorners ? scaled : 0
        let bottomRadius: CGFloat = selectedInfo.hasRoundedBottomCorners ? scaled : 0
        UnevenRoundedRectangle(
            topLeadingRadius: topRadius,
            bottomLeadingRadius: bottomRadius,
            bottomTrailingRadius: bottomRadius,
            topTrailingRadius: topRadius,
            style: .continuous
        )
        .fill(.secondary)
        .frame(width: 96, height: 60)
    }

    // MARK: Settings column

    @ViewBuilder
    private var settingsColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            monitorPicker
            radiusSlider
            fullscreenToggle
        }
        .frame(width: 240, alignment: .leading)
    }

    @ViewBuilder
    private var monitorPicker: some View {
        IceLabeledContent("Monitor") {
            HStack(spacing: 4) {
                Menu {
                    Button {
                        selectedScreenIdentifier = nil
                    } label: {
                        Text("Default")
                    }
                    if !screens.isEmpty {
                        Divider()
                        ForEach(screens, id: \.displayID) { screen in
                            Button {
                                selectedScreenIdentifier = screen.stableIdentifier
                            } label: {
                                monitorMenuRow(for: screen)
                            }
                        }
                    }
                } label: {
                    monitorSelectedLabel
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .frame(height: 24)

                Button {
                    useDefaults()
                } label: {
                    Image(systemName: "arrow.counterclockwise.circle.fill")
                }
                .buttonStyle(.borderless)
                .help(isUsingDefaults ? "Using defaults" : "Reset these screen shape settings")
                .disabled(isUsingDefaults)
            }
            .fixedSize()
        }
    }

    @ViewBuilder
    private var monitorSelectedLabel: some View {
        HStack(spacing: 6) {
            Text(currentMonitorName)
                .foregroundStyle(currentMonitorHasOverride ? .blue : .primary)
            if currentMonitorHasOverride {
                Circle()
                    .fill(.blue)
                    .frame(width: 6, height: 6)
            }
        }
    }

    @ViewBuilder
    private func monitorMenuRow(for screen: NSScreen) -> some View {
        let hasOverride = screenHasOverride(screen)
        HStack(spacing: 6) {
            Image(systemName: "display")
                .foregroundStyle(hasOverride ? .blue : .primary)
            Text(screen.localizedName)
                .foregroundStyle(hasOverride ? .blue : .primary)
            if hasOverride {
                Spacer(minLength: 8)
                Circle()
                    .fill(.blue)
                    .frame(width: 6, height: 6)
            }
        }
    }

    private var currentMonitorName: String {
        if let id = selectedScreenIdentifier,
           let screen = screens.first(where: { $0.stableIdentifier == id }) {
            return screen.localizedName
        }
        return "Default"
    }

    private var currentMonitorHasOverride: Bool {
        guard let id = selectedScreenIdentifier else {
            return false
        }
        guard let override = appearanceManager.configuration.screenShapeOverrides[id] else {
            return false
        }
        return override != appearanceManager.configuration.screenShapeInfo
    }

    private func screenHasOverride(_ screen: NSScreen) -> Bool {
        guard let id = screen.stableIdentifier else {
            return false
        }
        guard let override = appearanceManager.configuration.screenShapeOverrides[id] else {
            return false
        }
        return override != appearanceManager.configuration.screenShapeInfo
    }

    @ViewBuilder
    private var radiusSlider: some View {
        IceLabeledContent("Radius") {
            IceSlider(
                "\(Int(selectedInfo.cornerRadius))",
                value: bindingFor(\.cornerRadius),
                in: 3...35,
                step: 1
            )
            .frame(minHeight: .compactSliderMinHeight)
        }
    }

    @ViewBuilder
    private var fullscreenToggle: some View {
        Toggle("Display for fullscreen apps", isOn: bindingFor(\.showInFullscreen))
    }

    private func useDefaults() {
        var config = appearanceManager.configuration
        if let id = selectedScreenIdentifier {
            config.screenShapeOverrides.removeValue(forKey: id)
        } else {
            let oldDefaultInfo = config.screenShapeInfo
            config.screenShapeInfo = .default
            removeRedundantScreenShapeOverrides(
                from: &config,
                matching: [oldDefaultInfo, .default]
            )
        }
        appearanceManager.configuration = config
    }

    private func removeRedundantScreenShapeOverrides() {
        var config = appearanceManager.configuration
        let oldOverrides = config.screenShapeOverrides
        removeRedundantScreenShapeOverrides(
            from: &config,
            matching: [config.screenShapeInfo]
        )
        if config.screenShapeOverrides != oldOverrides {
            appearanceManager.configuration = config
        }
    }
}
