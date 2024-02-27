//
//  CustomTab.swift
//  Ice
//

import SwiftUI

/// A type that contains the information to construct
/// a tab in a custom tab view.
struct CustomTab {
    /// The tab's label view.
    let label: AnyView

    /// The tab's content view.
    let content: AnyView

    /// Creates a tab with the given label and content view.
    init<Label: View, Content: View>(
        @ViewBuilder label: () -> Label,
        @ViewBuilder content: () -> Content
    ) {
        self.label = AnyView(label())
        self.content = AnyView(content())
    }

    /// Creates a tab with the given label and content view.
    init<Content: View>(
        _ labelKey: LocalizedStringKey,
        @ViewBuilder content: () -> Content
    ) {
        self.init(label: { Text(labelKey) }, content: content)
    }
}
