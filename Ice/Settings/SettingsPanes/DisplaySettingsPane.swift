//
//  DisplaySettingsPane.swift
//  Ice
//

import SwiftUI

struct DisplaySettingsPane: View {
    @EnvironmentObject var appState: AppState
    @State private var availableDisplays: [DisplayInfo] = []
    
    private var manager: DisplaySettingsManager {
        appState.settingsManager.displaySettingsManager
    }
    
    private struct DisplayInfo: Identifiable {
        let id: CGDirectDisplayID
        let screen: NSScreen
        let name: String
        let isMain: Bool
        let hasNotch: Bool
        let resolution: String
        
        init(screen: NSScreen) {
            self.id = screen.displayID
            self.screen = screen
            self.isMain = screen == NSScreen.main
            self.hasNotch = screen.hasNotch
            
            let frame = screen.frame
            self.resolution = "\(Int(frame.width)) × \(Int(frame.height))"
            
            // Generate a display name
            if isMain {
                if hasNotch {
                    self.name = "Built-in Display (Main)"
                } else {
                    self.name = "Main Display"
                }
            } else {
                self.name = "External Display"
            }
        }
    }
    
    var body: some View {
        IceForm {
            IceSection("Ice Bar Configuration") {
                ForEach(availableDisplays) { displayInfo in
                    displayConfigurationRow(for: displayInfo)
                }
            }
        }
        .onAppear {
            updateAvailableDisplays()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            updateAvailableDisplays()
        }
    }
    
    @ViewBuilder
    private func displayConfigurationRow(for displayInfo: DisplayInfo) -> some View {
        let configuration = manager.configuration(for: displayInfo.id)
        
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(displayInfo.name)
                            .font(.headline)
                        
                        if displayInfo.isMain {
                            Text("MAIN")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.blue.opacity(0.2))
                                .foregroundColor(.blue)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                        
                        if displayInfo.hasNotch {
                            Text("NOTCH")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.purple.opacity(0.2))
                                .foregroundColor(.purple)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                    }
                    
                    Text(displayInfo.resolution)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Toggle("Use Ice Bar", isOn: Binding(
                    get: { configuration.useIceBar },
                    set: { newValue in
                        var newConfig = configuration
                        newConfig.useIceBar = newValue
                        manager.setConfiguration(newConfig, for: displayInfo.id)
                    }
                ))
            }
            
            if configuration.useIceBar {
                IcePicker("Location", selection: Binding(
                    get: { configuration.iceBarLocation },
                    set: { newValue in
                        var newConfig = configuration
                        newConfig.iceBarLocation = newValue
                        manager.setConfiguration(newConfig, for: displayInfo.id)
                    }
                )) {
                    ForEach(IceBarLocation.allCases) { location in
                        Text(location.localized).tag(location)
                    }
                }
                .annotation {
                    switch configuration.iceBarLocation {
                    case .dynamic:
                        Text("The Ice Bar's location changes based on context")
                    case .mousePointer:
                        Text("The Ice Bar is centered below the mouse pointer")
                    case .iceIcon:
                        Text("The Ice Bar is centered below the Ice icon")
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
    
    private func updateAvailableDisplays() {
        let displays = NSScreen.screens.map { DisplayInfo(screen: $0) }
        // Sort: main display first, then by resolution (larger first)
        availableDisplays = displays.sorted { lhs, rhs in
            if lhs.isMain != rhs.isMain {
                return lhs.isMain
            }
            return lhs.screen.frame.width * lhs.screen.frame.height > rhs.screen.frame.width * rhs.screen.frame.height
        }
        
        // Ensure all displays have configurations
        for displayInfo in availableDisplays {
            if manager.configuration(for: displayInfo.id).useIceBar == false && 
               manager.displayConfigurations[displayInfo.id] == nil {
                // Only set a default if no configuration exists
                manager.setConfiguration(DisplayIceBarConfiguration(), for: displayInfo.id)
            }
        }
    }
}

#Preview {
    DisplaySettingsPane()
        .environmentObject(AppState())
}
