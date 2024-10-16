//
//  MenuBarProfileManager.swift
//  Ice
//

import Combine
import Foundation

@MainActor
class MenuBarProfileManager: ObservableObject {
    enum ProfileError: Error {
        case noActiveProfile
    }

    @Published private(set) var profiles = [MenuBarProfile]()

    @Published private(set) var activeProfileName = MenuBarProfile.defaultProfileName

    private let encoder = PropertyListEncoder()

    private let decoder = PropertyListDecoder()

    private var cancellables = Set<AnyCancellable>()

    var activeProfile: MenuBarProfile? {
        profile(withName: activeProfileName)
    }

    func performSetup() {
        Task {
            try? await Task.sleep(for: .seconds(0.5))
            initializeProfiles()
            configureCancellables()
        }
    }

    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        $activeProfileName
            .receive(on: DispatchQueue.main)
            .sink { name in
                Defaults.set(name, forKey: .activeProfileName)
            }
            .store(in: &c)

        $profiles
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.saveProfiles()
            }
            .store(in: &c)

        cancellables = c
    }

    private func initializeProfiles() {
        if let array = Defaults.array(forKey: .profiles) {
            do {
                let data = try PropertyListSerialization.data(fromPropertyList: array, format: .xml, options: 0)
                profiles = try decoder.decode([MenuBarProfile].self, from: data)
            } catch {
                Logger.profileManager.error("Error decoding profiles: \(error)")
            }
        }
        // If any profiles were decoded, exit early.
        guard profiles.isEmpty else {
            return
        }
        // Create a new default profile.
        let profile = MenuBarProfile(name: MenuBarProfile.defaultProfileName, configuration: .current())
        profiles.append(profile)
    }

    private func saveProfiles() {
        do {
            let data = try encoder.encode(profiles)
            let array = try PropertyListSerialization.propertyList(from: data, format: nil)
            Defaults.set(array, forKey: .profiles)
        } catch {
            Logger.profileManager.error("Error encoding menu bar profiles: \(error)")
        }
    }

    func profile(withName name: String) -> MenuBarProfile? {
        profiles.first { profile in
            profile.name == name
        }
    }

    func setActiveProfileConfiguration(_ configuration: MenuBarItemConfiguration) throws {
        guard let index = profiles.firstIndex(where: { $0.name == activeProfileName }) else {
            throw ProfileError.noActiveProfile
        }
        profiles[index].configuration = configuration
    }

    func setActiveProfileName(_ name: String) throws {
        guard let index = profiles.firstIndex(where: { $0.name == activeProfileName }) else {
            throw ProfileError.noActiveProfile
        }
        profiles[index].name = name
        activeProfileName = name
    }
}

// MARK: - Logger
private extension Logger {
    static let profileManager = Logger(category: "MenuBarProfileManager")
}
