//
//  Permission.swift
//  Ice
//

import AXSwift
import Combine
import Cocoa
import ScreenCaptureKit

// MARK: - Permission

/// An object that encapsulates the behavior of checking for and requesting
/// a specific permission for the app.
@MainActor
class Permission: ObservableObject, Identifiable {
    /// A Boolean value that indicates whether the app has this permission.
    @Published private(set) var hasPermission = false

    /// The title of the permission.
    let title: String
    /// Descriptive details for the permission.
    let details: [String]
    /// A Boolean value that indicates if the app can work without this permission.
    let isRequired: Bool

    /// The URL of the settings pane to open.
    private let settingsURL: URL?
    /// The function that checks permissions.
    private let check: () -> Bool
    /// The function that requests permissions.
    private let request: () -> Void

    /// Observer that runs on a timer to check permissions.
    private var timerCancellable: AnyCancellable?

    /// Creates a permission.
    ///
    /// - Parameters:
    ///   - title: The title of the permission.
    ///   - details: Descriptive details for the permission.
    ///   - isRequired: A Boolean value that indicates if the app can work without this permission.
    ///   - settingsURL: The URL of the settings pane to open.
    ///   - check: A function that checks permissions.
    ///   - request: A function that requests permissions.
    init(
        title: String,
        details: [String],
        isRequired: Bool,
        settingsURL: URL?,
        check: @escaping () -> Bool,
        request: @escaping () -> Void
    ) {
        self.title = title
        self.details = details
        self.isRequired = isRequired
        self.settingsURL = settingsURL
        self.check = check
        self.request = request
        if AppLanguage.hasCompletedSetup {
            startCheck()
        }
    }

    /// Sets up the internal observers for the permission.
    private func configureCancellables() {
        timerCancellable = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .merge(with: Just(.now))
            .merge(with: NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification).map { _ in Date.now })
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refresh()
            }
    }

    func refresh() {
        guard AppLanguage.hasCompletedSetup else {
            return
        }
        let granted = check()
        if granted != hasPermission {
            hasPermission = granted
        }
    }

    func startCheck() {
        guard AppLanguage.hasCompletedSetup else {
            return
        }
        refresh()
        configureCancellables()
    }

    /// Performs the request and opens the System Settings app to the appropriate pane.
    func performRequest() {
        guard AppLanguage.hasCompletedSetup else {
            return
        }
        startCheck()
        request()
        if let settingsURL {
            NSWorkspace.shared.open(settingsURL)
        }
    }

    /// Stops running the permission check.
    func stopCheck() {
        timerCancellable?.cancel()
        timerCancellable = nil
    }
}

// MARK: - AccessibilityPermission

final class AccessibilityPermission: Permission {
    init() {
        super.init(
            title: String(localized: "Accessibility"),
            details: [
                String(localized: "Get real-time information about the menu bar."),
                String(localized: "Arrange menu bar items."),
            ],
            isRequired: true,
            settingsURL: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"),
            check: {
                checkIsProcessTrusted()
            },
            request: {
                checkIsProcessTrusted(prompt: true)
            }
        )
    }
}

// MARK: - ScreenRecordingPermission

final class ScreenRecordingPermission: Permission {
    init() {
        super.init(
            title: String(localized: "Screen Recording"),
            details: [
                String(localized: "Edit the menu bar's appearance."),
                String(localized: "Display images of individual menu bar items."),
            ],
            isRequired: false,
            settingsURL: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"),
            check: {
                ScreenCapture.checkPermissions()
            },
            request: {
                ScreenCapture.requestPermissions()
            }
        )
    }
}
