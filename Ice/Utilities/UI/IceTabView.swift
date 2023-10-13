//
//  IceTabView.swift
//  Ice
//

import SwiftUI

/// A tab view that displays its tabs with the ``IceButtonStyle``.
struct IceTabView: View {
    /// Index of the currently selected tab.
    @Binding var selection: Int

    /// The tabs in the tab view.
    let tabs: [IceTab]

    /// Creates a tab view with the given tabs.
    init(selection: Binding<Int>, @IceTabBuilder tabs: () -> [IceTab]) {
        self._selection = selection
        self.tabs = tabs()
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 5) {
                ForEach(0..<tabs.count, id: \.self) { index in
                    IceTabButton(
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
        .buttonStyle(IceButtonStyle())
    }

    @ViewBuilder
    private var selectedTabContent: some View {
        if tabs.indices.contains(selection) {
            tabs[selection].content
        }
    }
}

/// A type that contains the to construct a tab in an ``IceTabView``.
struct IceTab {
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
private struct IceTabButton: View {
    @State private var isHovering = false
    @Binding var selection: Int

    let tab: IceTab
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
        .iceButtonConfiguration {
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
enum IceTabBuilder {
    static func buildBlock(_ components: IceTab...) -> [IceTab] {
        components
    }
}

#Preview {
    IceTabView(selection: .constant(0)) {
        IceTab {
            Text("Tab 1")
        } content: {
            Text("Tab 1 Content")
        }
        IceTab {
            Text("Tab 2")
        } content: {
            Text("Tab 2 Content")
        }
        IceTab {
            Text("Tab 3")
        } content: {
            Text("Tab 3 Content")
        }
    }
}
