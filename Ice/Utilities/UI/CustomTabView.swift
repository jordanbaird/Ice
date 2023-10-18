//
//  CustomTabView.swift
//  Ice
//

import SwiftUI

/// A tab view that displays its tabs with the ``CustomButtonStyle``.
struct CustomTabView: View {
    /// Index of the currently selected tab.
    @Binding var selection: Int

    /// The tabs in the tab view.
    let tabs: [CustomTab]

    /// Creates a tab view with the given selection and tabs.
    init(
        selection: Binding<Int>,
        @CustomTabBuilder tabs: () -> [CustomTab]
    ) {
        self._selection = selection
        self.tabs = tabs()
    }

    var body: some View {
        VStack(spacing: 0) {
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
        .buttonStyle(CustomButtonStyle())
    }

    @ViewBuilder
    private var selectedTabContent: some View {
        if tabs.indices.contains(selection) {
            tabs[selection].content
        }
    }
}

/// A type that contains the information to construct a
/// tab in a ``CustomTabView``.
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
        .customButtonConfiguration {
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
enum CustomTabBuilder {
    static func buildBlock(_ components: CustomTab...) -> [CustomTab] {
        components
    }
}

#Preview {
    CustomTabView(selection: .constant(0)) {
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
