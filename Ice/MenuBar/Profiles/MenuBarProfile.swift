//
//  MenuBarProfile.swift
//  Ice
//

import Combine
import Foundation

/// A representation of a menu bar profile.
@MainActor
final class MenuBarProfile: ObservableObject {
    /// The profile's name.
    @Published var name: String

    /// The profile's item configuration.
    @Published var configuration: MenuBarItemConfiguration

    /// Storage for internal observers.
    private var cancellables = Set<AnyCancellable>()

    /// Creates a profile with the given name and item configuration.
    init(name: String, configuration: MenuBarItemConfiguration) {
        self.name = name
        self.configuration = configuration
        configureCancellables()
    }

    /// Configures the internal observers for the profile.
    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        Timer.publish(every: 5, on: .main, in: .default)
            .autoconnect()
            .merge(with: Just(.now))
            .sink { [weak self] _ in
                self?.validate()
            }
            .store(in: &c)

        cancellables = c
    }

    /// Validates the profile's configuration.
    func validate() {
        configuration.validate()
    }
}

// MARK: Default Profile
extension MenuBarProfile {
    /// The name of the default profile.
    static let defaultProfileName = "Default"
}

// MARK: MenuBarProfile: Codable
extension MenuBarProfile: @preconcurrency Codable {
    private enum CodingKeys: String, CodingKey {
        case name = "Name"
        case configuration = "Items"
    }

    convenience init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            name: container.decode(String.self, forKey: .name),
            configuration: container.decode(MenuBarItemConfiguration.self, forKey: .configuration)
        )
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(configuration, forKey: .configuration)
    }
}
