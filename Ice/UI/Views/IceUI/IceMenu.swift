//
//  IceMenu.swift
//  Ice
//

import SwiftUI

struct IceMenu<Label: View, Content: View>: View {
    @State private var isHovering = false

    private let label: Label
    private let content: Content
    private let action: (AnyHashable) -> Void

    init(
        action: @escaping (AnyHashable) -> Void,
        @ViewBuilder content: () -> Content,
        @ViewBuilder label: () -> Label
    ) {
        self.label = label()
        self.content = content()
        self.action = action
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            IceMenuButton()
                .allowsHitTesting(false)
                .opacity(isHovering ? 1 : 0)

            _VariadicView.Tree(IceMenuLayout(label: label, action: action)) {
                content
            }
        }
        .frame(height: 22)
        .fixedSize()
        .onHover { hovering in
            isHovering = hovering
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

private struct IceMenuLayout<Label: View>: _VariadicView_UnaryViewRoot {
    let label: Label
    let action: (AnyHashable) -> Void

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
            label
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.visible)
        .baselineOffset(1)
        .padding(.leading, 5)
    }
}
