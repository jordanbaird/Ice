//
//  StarRequestPrompt.swift
//  Ice
//

import AppKit

/// A one-time prompt that asks the user to star the project on GitHub.
///
/// The prompt is shown exactly once per app version, and only when that
/// version was installed as an update on top of a previously launched version.
/// It never appears on a fresh first install, and it can be permanently
/// dismissed with the "Never" button.
enum StarRequestPrompt {
    /// The repository URL for the project.
    static let repositoryURL = URL(string: "https://github.com/cavaldos/Ice") ?? URL(fileURLWithPath: "/")

    /// Presents the star request if the current version is an update that has
    /// not been asked about yet.
    ///
    /// - Parameter appState: The shared app state, used to activate the app so
    ///   that the alert is able to process input.
    @MainActor
    static func presentIfNeeded(appState: AppState) {
        // The user asked never to be asked again.
        guard !Defaults.bool(forKey: .hasDeclinedStarRequest) else {
            return
        }

        let currentVersion = Constants.versionString

        // No version recorded yet means this is a fresh install: record the
        // current version so the prompt can fire after the first update, but
        // do not ask now.
        guard let recordedVersion = Defaults.string(forKey: .starRequestVersion) else {
            Defaults.set(currentVersion, forKey: .starRequestVersion)
            return
        }

        // Same version as the last launch, so nothing was updated.
        guard recordedVersion != currentVersion else {
            return
        }

        // Record the version before presenting so the prompt can never be
        // shown twice for the same version, even if it is dismissed.
        Defaults.set(currentVersion, forKey: .starRequestVersion)

        present(appState: appState)
    }

    /// Presents the star request alert.
    ///
    /// - Parameter appState: The shared app state.
    @MainActor
    private static func present(appState: AppState) {
        let alert = NSAlert()
        alert.messageText = "Enjoying Ice?"
        alert.informativeText = """
            You just updated to Ice \(Constants.versionString). \
            If Ice has been useful to you, a GitHub star helps other people find it.
            """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Star on GitHub")
        alert.addButton(withTitle: "Maybe Later")
        alert.addButton(withTitle: "Never")

        // Ice runs as a hidden background app (LSUIElement), so it must be
        // activated before the alert can receive input — otherwise the alert
        // shows but never processes the response (jordanbaird/Ice#681).
        appState.activate(withPolicy: .regular)

        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn:
            NSWorkspace.shared.open(repositoryURL)
        case .alertThirdButtonReturn:
            // The opt-out is permanent, so the prompt never returns.
            Defaults.set(true, forKey: .hasDeclinedStarRequest)
        default:
            // "Maybe Later" still means not twice for this version, which the
            // version recorded above already guarantees.
            break
        }

        // Hand the menu bar back to the app the user was using.
        appState.deactivate(withPolicy: .accessory)
    }
}
