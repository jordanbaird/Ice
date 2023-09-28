//
//  RemoveSidebarToggle.swift
//  Ice
//

import SwiftUI

/// A modifier that removes the sidebar toggle button from a
/// `NavigationSplitView`, while keeping the window's toolbar.
@available(macOS 14.0, *)
private struct RemoveSidebarToggleModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .toolbar(removing: .sidebarToggle)
            .toolbar { Color.clear }
    }
}

/// A modifier that removes the sidebar toggle button from a
/// `NavigationSplitView`, while keeping the window's toolbar.
///
/// This version of the modifier exists to support macOS 13,
/// as SwiftUI didn't have a built-in way to remove the sidebar
/// toggle button until macOS 14.
@available(macOS, deprecated: 14.0)
private struct RemoveSidebarToggleModifierDeprecated: ViewModifier {
    @State private var window: NSWindow?
    private let itemIdentifier = "com.apple.SwiftUI.navigationSplitView.toggleSidebar"

    func body(content: Content) -> some View {
        content
            .onChange(of: window?.toolbar?.items) { items in
                let item = items?.first {
                    $0.itemIdentifier.rawValue == itemIdentifier
                }
                item?.view?.isHidden = true
            }
            .readWindow(window: $window)
    }
}

extension View {
    /// Removes the sidebar toggle button from a `NavigationSplitView`.
    @ViewBuilder
    func removeSidebarToggle() -> some View {
        if #available(macOS 14, *) {
            modifier(RemoveSidebarToggleModifier())
        } else {
            modifier(RemoveSidebarToggleModifierDeprecated())
        }
    }
}
