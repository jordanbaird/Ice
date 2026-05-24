//
//  LocalizationManager.swift
//  Ice
//

import Combine
import SwiftUI

/// Manager that handles runtime language switching.
@MainActor
final class LocalizationManager: ObservableObject {
    /// The currently selected language.
    @Published var language: AppLanguage = .system

    /// The resolved language (follows system when `.system` is selected).
    private(set) var resolvedLanguage: Locale.LanguageCode = .english

    /// Shared singleton for AppKit code (e.g., NSMenu).
    static let shared = LocalizationManager()

    /// The app state.
    private weak var appState: AppState?

    /// Storage for internal observers.
    private var cancellables = Set<AnyCancellable>()

    /// Creates a localization manager with the given app state.
    init(appState: AppState? = nil) {
        self.appState = appState
    }

    /// Sets up the manager.
    func performSetup() {
        loadInitialState()
        configureCancellables()
    }

    /// Returns a localized string for the given key.
    func localized(_ key: LocalizationKey) -> String {
        switch resolvedLanguage {
        case .chinese:
            return key.chinese
        default:
            return key.rawValue
        }
    }

    /// Returns a localized string as a LocalizedStringKey.
    func localizedKey(_ key: LocalizationKey) -> LocalizedStringKey {
        LocalizedStringKey(localized(key))
    }

    /// Static version that reads directly from UserDefaults (for AppKit code).
    /// This does NOT require the manager to be set up via performSetup().
    static func localizedStatic(_ key: LocalizationKey) -> String {
        let language: AppLanguage
        if let rawValue = Defaults.string(forKey: .appLanguage),
           let lang = AppLanguage(rawValue: rawValue) {
            language = lang
        } else {
            language = .system
        }
        let resolved = language.resolvedLanguage
        switch resolved {
        case .chinese: return key.chinese
        default: return key.rawValue
        }
    }

    // MARK: - Private

    private func loadInitialState() {
        Defaults.ifPresent(key: .appLanguage) { (value: String) in
            if let lang = AppLanguage(rawValue: value) {
                language = lang
            }
        }
        updateResolvedLanguage()
    }

    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        $language
            .receive(on: DispatchQueue.main)
            .sink { language in
                Defaults.set(language.rawValue, forKey: .appLanguage)
            }
            .store(in: &c)

        $language
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateResolvedLanguage()
            }
            .store(in: &c)

        cancellables = c
    }

    private func updateResolvedLanguage() {
        resolvedLanguage = language.resolvedLanguage
    }
}

// MARK: LocalizationManager: BindingExposable
extension LocalizationManager: BindingExposable { }

