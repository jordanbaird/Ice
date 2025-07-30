//
//  DisplaySettingsManager.swift
//  Ice
//

import Combine
import Foundation

/// Configuration for Ice Bar on a specific display.
struct DisplayIceBarConfiguration: Codable, Hashable {
    /// Whether to use Ice Bar on this display.
    var useIceBar: Bool
    
    /// The location where the Ice Bar appears on this display.
    var iceBarLocation: IceBarLocation
    
    init(useIceBar: Bool = false, iceBarLocation: IceBarLocation = .dynamic) {
        self.useIceBar = useIceBar
        self.iceBarLocation = iceBarLocation
    }
}

/// Manages per-display settings.
@MainActor
final class DisplaySettingsManager: ObservableObject {
    /// Per-display Ice Bar configurations, keyed by display ID.
    @Published var displayConfigurations: [CGDirectDisplayID: DisplayIceBarConfiguration] = [:]
    
    /// Publisher that emits whenever any display's Ice Bar usage changes.
    var anyIceBarUsageChanged: AnyPublisher<Bool, Never> {
        $displayConfigurations
            .map { configurations in
                configurations.values.contains { $0.useIceBar }
            }
            .removeDuplicates()
            .eraseToAnyPublisher()
    }
    
    /// Encoder for properties.
    private let encoder = JSONEncoder()
    
    /// Decoder for properties.
    private let decoder = JSONDecoder()
    
    /// Storage for internal observers.
    private var cancellables = Set<AnyCancellable>()
    
    /// The shared app state.
    private(set) weak var appState: AppState?
    
    init(appState: AppState) {
        self.appState = appState
    }
    
    func performSetup() {
        loadInitialState()
        configureCancellables()
    }
    
    private func loadInitialState() {
        if let data = Defaults.data(forKey: .displayConfigurations) {
            do {
                // Decode as [String: DisplayIceBarConfiguration] first, then convert keys
                let stringKeyedDict = try decoder.decode([String: DisplayIceBarConfiguration].self, from: data)
                displayConfigurations = Dictionary(
                    uniqueKeysWithValues: stringKeyedDict.compactMap { (key, value) in
                        guard let displayID = CGDirectDisplayID(key) else { return nil }
                        return (displayID, value)
                    }
                )
            } catch {
                Logger.displaySettingsManager.error("Error decoding display configurations: \(error)")
            }
        }
        
        // Migrate from legacy useIceBar setting
        migrateFromLegacySetting()
    }
    
    private func migrateFromLegacySetting() {
        // If we have the old useIceBar setting but no display configurations,
        // apply it to all connected displays
        guard displayConfigurations.isEmpty else { return }
        
        let legacyUseIceBar = Defaults.bool(forKey: .useIceBar) ?? false
        let legacyIceBarLocation = IceBarLocation(rawValue: Defaults.integer(forKey: .iceBarLocation)) ?? .dynamic
        
        if legacyUseIceBar || legacyIceBarLocation != .dynamic {
            for screen in NSScreen.screens {
                let config = DisplayIceBarConfiguration(
                    useIceBar: legacyUseIceBar,
                    iceBarLocation: legacyIceBarLocation
                )
                displayConfigurations[screen.displayID] = config
            }
        }
    }
    
    private func configureCancellables() {
        var c = Set<AnyCancellable>()
        
        $displayConfigurations
            .receive(on: DispatchQueue.main)
            .sink { [weak self] configurations in
                guard let self else { return }
                do {
                    // Convert to [String: DisplayIceBarConfiguration] for JSON encoding
                    let stringKeyedDict = Dictionary(
                        uniqueKeysWithValues: configurations.map { (key, value) in
                            (String(key), value)
                        }
                    )
                    let data = try encoder.encode(stringKeyedDict)
                    Defaults.set(data, forKey: .displayConfigurations)
                } catch {
                    Logger.displaySettingsManager.error("Error encoding display configurations: \(error)")
                }
            }
            .store(in: &c)
        
        // React to display changes
        NotificationCenter.default
            .publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.ensureConfigurationsForAllDisplays()
            }
            .store(in: &c)
        
        cancellables = c
    }
    
    /// Ensures all connected displays have configurations.
    private func ensureConfigurationsForAllDisplays() {
        for screen in NSScreen.screens {
            if displayConfigurations[screen.displayID] == nil {
                displayConfigurations[screen.displayID] = DisplayIceBarConfiguration()
            }
        }
    }
    
    /// Returns the Ice Bar configuration for the given display.
    func configuration(for displayID: CGDirectDisplayID) -> DisplayIceBarConfiguration {
        return displayConfigurations[displayID] ?? DisplayIceBarConfiguration()
    }
    
    /// Sets the Ice Bar configuration for the given display.
    func setConfiguration(_ configuration: DisplayIceBarConfiguration, for displayID: CGDirectDisplayID) {
        displayConfigurations[displayID] = configuration
    }
    
    /// Returns whether Ice Bar should be used on the given display.
    func shouldUseIceBar(on displayID: CGDirectDisplayID) -> Bool {
        return configuration(for: displayID).useIceBar
    }
    
    /// Returns whether Ice Bar should be used on the given screen.
    func shouldUseIceBar(on screen: NSScreen) -> Bool {
        return shouldUseIceBar(on: screen.displayID)
    }
    
    /// Returns whether any display has Ice Bar enabled.
    var hasAnyDisplayWithIceBar: Bool {
        return displayConfigurations.values.contains { $0.useIceBar }
    }
}

// MARK: DisplaySettingsManager: BindingExposable
extension DisplaySettingsManager: BindingExposable { }

// MARK: - Logger
private extension Logger {
    static let displaySettingsManager = Logger(category: "DisplaySettingsManager")
}
