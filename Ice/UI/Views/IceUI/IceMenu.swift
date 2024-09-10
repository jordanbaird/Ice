//
//  IceMenu.swift
//  Ice
//

import SwiftUI

struct IceMenu<Title: View, Label: View, Content: View>: View {
    @State private var isHovering = false

    private let title: Title
    private let label: Label
    private let content: Content
    private let action: (any Hashable) -> Void

    /// Creates a menu with the given action, content, titlel, and label.
    ///
    /// - Parameters:
    ///   - action: An action to perform when a menu item is clicked. The action takes
    ///     a hashable id as its parameter.
    ///   - content: A group of menu items.
    ///   - title: A view to display inside the menu.
    ///   - label: A view to display as an external label for the menu.
    init(
        action: @escaping (any Hashable) -> Void,
        @ViewBuilder content: () -> Content,
        @ViewBuilder title: () -> Title,
        @ViewBuilder label: () -> Label
    ) {
        self.title = title()
        self.label = label()
        self.content = content()
        self.action = action
    }

    var body: some View {
        IceLabeledContent {
            ZStack(alignment: .trailing) {
                IceMenuButton()
                    .allowsHitTesting(false)
                    .opacity(isHovering ? 1 : 0)

                _VariadicView.Tree(IceMenuLayout(title: title, action: action)) {
                    content
                }
            }
            .frame(height: 22)
            .fixedSize()
            .onHover { hovering in
                isHovering = hovering
            }
        } label: {
            label
        }
    }
}

private struct IceMenuButton: NSViewRepresentable {
    func makeNSView(context: Context) -> NSButton {
        let button = NSButton()
        button.title = ""
        return button
    }

    func updateNSView(_ nsView: NSButton, context: Context) { }
}

private struct IceMenuLayout<Title: View>: _VariadicView_UnaryViewRoot {
    let title: Title
    let action: (any Hashable) -> Void

    func body(children: _VariadicView.Children) -> some View {
        Menu {
            ForEach(children) { child in
                Button {
                    action(child.id)
                } label: {
                    child
                }
            }
        } label: {
            title
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.visible)
        .labelStyle(.titleAndIcon)
        .baselineOffset(1)
        .padding(.leading, 5)
    }
}
