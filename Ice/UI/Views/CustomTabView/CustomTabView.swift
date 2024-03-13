//
//  CustomTabView.swift
//  Ice
//

import SwiftUI

/// A tab view that displays its tabs with a custom
/// button style.
struct CustomTabView: View {
    /// Index of the currently selected tab.
    @Binding var selection: Int

    /// The tabs in the tab view.
    let tabs: [CustomTab]

    /// Creates a tab view with the given selection
    /// and tabs.
    init(
        selection: Binding<Int>,
        @CustomTabBuilder tabs: () -> [CustomTab]
    ) {
        self._selection = selection
        self.tabs = tabs()
    }

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            Divider()
            content
        }
        .onAppear {
            if !tabs.indices.contains(selection) {
                selection = 0
            }
        }
    }

    @ViewBuilder
    private var tabBar: some View {
        HStack(spacing: 5) {
            ForEach(0..<tabs.count, id: \.self) { index in
                CustomTabButton(
                    selection: $selection,
                    tab: tabs[index],
                    index: index
                )
            }
        }
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity)
        .background(Material.regular)
    }

    @ViewBuilder
    private var selectedTabContent: some View {
        if tabs.indices.contains(selection) {
            tabs[selection].content
        }
    }

    @ViewBuilder
    private var content: some View {
        GeometryReader { proxy in
            selectedTabContent
                .frame(
                    width: proxy.size.width,
                    height: proxy.size.height
                )
        }
    }
}

/// Custom button to display as a tab above a tab view.
private struct CustomTabButton: View {
    @State private var isHovering = false
    @Binding var selection: Int

    let tab: CustomTab
    let index: Int

    var isSelected: Bool {
        selection == index
    }

    var body: some View {
        Button {
            selection = index
        } label: {
            tab.label
        }
        .customButtonConfiguration { configuration in
            configuration.bezelOpacity = isSelected ? 1 : isHovering ? 0.5 : 0
            configuration.isHighlighted = isSelected
            configuration.labelForegroundColor = .primary.opacity(isSelected ? 1 : 0.75)
        }
        .onHover { hovering in
            isHovering = hovering
        }
        .buttonStyle(.custom)
        .customButtonConfiguration { configuration in
            configuration.labelPadding.top = -1
            configuration.labelPadding.bottom = -1
            configuration.labelPadding.leading = -1
            configuration.labelPadding.trailing = -1
        }
    }
}

#Preview {
    StateView(initialValue: 0) { state in
        CustomTabView(selection: state) {
            CustomTab {
                Text("Tab 1")
            } content: {
                Text("Tab 1 Content")
            }
            CustomTab {
                Text("Tab 2")
            } content: {
                Text("Tab 2 Content")
            }
            CustomTab {
                Text("Tab 3")
            } content: {
                Text("Tab 3 Content")
            }
        }
    }
}
