//
//  AppNavigationState.swift
//  Ice
//

import Combine

/// The model for app-wide navigation.
@MainActor
final class AppNavigationState: ObservableObject {
    @Published var appNavigationIdentifier: AppNavigationIdentifier = .idle
    @Published var settingsNavigationIdentifier: SettingsNavigationIdentifier = .general
}
