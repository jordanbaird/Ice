//
//  IceWindow.swift
//  Ice
//

import SwiftUI

// MARK: - IceWindow

/// A custom scene representing one of Ice's windows.
struct IceWindow<Content: View>: Scene {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    /// The window's identifier.
    let id: IceWindowIdentifier

    /// The window's content view.
    let content: Content

    /// Creates a window with an identifier constant.
    ///
    /// - Parameters:
    ///   - id: A custom identifier constant.
    ///   - content: The content view to display in the window.
    init(id: IceWindowIdentifier, @ViewBuilder content: () -> Content) {
        self.id = id
        self.content = content()
    }

    var body: some Scene {
        MenuBarExtra("", isInserted: .constant(false)) { }.once {
            initializeWindow()
        }

        Window(id.titleKey, id: id.rawValue) {
            content.onWindowChange { window in
                guard let window else {
                    return
                }
                window.collectionBehavior.insert(.moveToActiveSpace)
            }
        }
    }

    private func initializeWindow() {
        openWindow(id: id)
        dismissWindow(id: id)
    }
}

// MARK: - IceWindowIdentifier

/// Custom identifier constants uses to create Ice's windows.
enum IceWindowIdentifier: String, Sendable, CustomStringConvertible {
    /// The identifier for Ice's main settings window.
    case settings = "SettingsWindow"

    /// The identifier for Ice's permissions window.
    case permissions = "PermissionsWindow"

    /// The non-localized title of the corresponding window.
    ///
    /// - Note: Use ``titleKey`` to get the localized title.
    var titleString: String {
        switch self {
        case .settings: "Ice"
        case .permissions: "Permissions"
        }
    }

    /// The localized title of the corresponding window.
    ///
    /// - Note: Use ``titleString`` to get the non-localized title.
    var titleKey: LocalizedStringKey {
        LocalizedStringKey(titleString)
    }

    /// A textual representation of the identifier.
    var description: String {
        rawValue
    }
}

// MARK: - OpenWindowAction

extension OpenWindowAction {
    /// Opens the corresponding window for the given identifier.
    ///
    /// - Parameter id: An identifier for one of Ice's windows.
    func callAsFunction(id: IceWindowIdentifier) {
        callAsFunction(id: id.rawValue)
    }
}

// MARK: - DismissWindowAction

extension DismissWindowAction {
    /// Dismisses the corresponding window for the given identifier.
    ///
    /// - Parameter id: An identifier for one of Ice's windows.
    func callAsFunction(id: IceWindowIdentifier) {
        callAsFunction(id: id.rawValue)
    }
}
