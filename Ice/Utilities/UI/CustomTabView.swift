//
//  CustomTabView.swift
//  Ice
//

import SwiftUI

/// A tab view that displays its tabs with Ice's ``SettingsButtonStyle``.
struct CustomTabView: View {
    /// Index of the currently selected tab.
    @State private var selection: Int = 0

    /// All tabs in the tab view.
    let tabs: [Tab]

    /// Creates a tab view with the given tabs.
    init(@TabBuilder tabs: () -> [Tab]) {
        self.tabs = tabs()
    }

    /// The tab view's body.
    var body: some View {
        VStack(spacing: 5) {
            HStack(spacing: 1) {
                ForEach(0..<tabs.count, id: \.self) { index in
                    TabButton(
                        selection: $selection,
                        tab: tabs[index],
                        index: index
                    )
                }
            }
            .padding(.top, 5)

            Divider()

            tabs[selection].content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(SettingsButtonStyle())
    }
}

/// A type that contains the to construct a tab in a ``CustomTabView``.
struct Tab {
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
}

/// Custom button to display as a tab above a tab view.
private struct TabButton: View {
    /// A Boolean value indicating whether the button is
    /// being hovered over.
    @State private var isHovering = false

    /// A binding to the index of the currently selected
    /// tab.
    @Binding var selection: Int

    /// The button's tab representation.
    let tab: Tab

    /// The index of this button in the tab view.
    let index: Int

    /// A Boolean value indicating whether the tab button
    /// is selected.
    private var isSelected: Bool {
        selection == index
    }

    /// The button's body.
    var body: some View {
        Button {
            selection = index
        } label: {
            tab.label
        }
        .settingsButtonConfiguration {
            $0.bezelOpacity = isSelected ? 1 : isHovering ? 0.5 : 0
            $0.isHighlighted = isSelected
            $0.labelForegroundColor = .primary.opacity(isSelected ? 1 : 0.75)
        }
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

/// A result builder type that builds an array of tabs
/// for a custom tab view.
@resultBuilder
enum TabBuilder {
    static func buildBlock(_ components: Tab...) -> [Tab] {
        components
    }
}

#Preview {
    CustomTabView {
        Tab {
            Text("Tab 1")
        } content: {
            Text("Tab 1 Content")
        }
        Tab {
            Text("Tab 2")
        } content: {
            Text("Tab 2 Content")
        }
        Tab {
            Text("Tab 3")
        } content: {
            Text("Tab 3 Content")
        }
    }
}
