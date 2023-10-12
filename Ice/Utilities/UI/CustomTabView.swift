//
//  CustomTabView.swift
//  Ice
//

import SwiftUI

/// A tab view that displays its tabs with Ice's ``SettingsButtonStyle``.
struct CustomTabView: View {
    /// Index of the currently selected tab.
    @Binding var selection: Int

    /// All tabs in the tab view.
    let tabs: [Tab]

    /// Creates a tab view with the given tabs.
    init(selection: Binding<Int>, @TabBuilder tabs: () -> [Tab]) {
        self._selection = selection
        self.tabs = tabs()
    }

    /// The tab view's body.
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 5) {
                Spacer()
                ForEach(0..<tabs.count, id: \.self) { index in
                    TabButton(
                        selection: $selection,
                        tab: tabs[index],
                        index: index
                    )
                }
                Spacer()
            }
            .padding(.vertical, 5)
            .background(Material.regular)

            Divider()

            GeometryReader { proxy in
                selectedTabContent
                    .frame(
                        width: proxy.size.width,
                        height: proxy.size.height
                    )
            }
        }
        .onAppear {
            if !tabs.indices.contains(selection) {
                selection = 0
            }
        }
        .buttonStyle(SettingsButtonStyle())
    }

    @ViewBuilder
    private var selectedTabContent: some View {
        if tabs.indices.contains(selection) {
            tabs[selection].content
        }
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
    CustomTabView(selection: .constant(0)) {
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
