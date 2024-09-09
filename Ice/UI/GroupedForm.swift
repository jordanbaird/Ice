//
//  GroupedForm.swift
//  Ice
//

import SwiftUI

/// A form that uses the `grouped` style.
struct GroupedForm<Content: View>: View {
    private let scrollBounceBehavior: ScrollBounceBehavior
    private let backgroundVisibility: Visibility
    private let content: Content

    /// Creates a grouped form with the given scroll behavior, background
    /// visibility, and content.
    /// - Parameters:
    ///   - scrollBounceBehavior: The bounce behavior of the form's scroll view.
    ///   - backgroundVisibility: The visibility of the background of the form's scroll view.
    ///   - content: The form's content.
    init(
        scrollBounceBehavior: ScrollBounceBehavior = .basedOnSize,
        backgroundVisibility: Visibility = .hidden,
        @ViewBuilder content: () -> Content
    ) {
        self.scrollBounceBehavior = scrollBounceBehavior
        self.backgroundVisibility = backgroundVisibility
        self.content = content()
    }

    var body: some View {
        Form {
            content
        }
        .formStyle(.grouped)
        .scrollBounceBehavior(scrollBounceBehavior)
        .scrollContentBackground(backgroundVisibility)
    }
}
