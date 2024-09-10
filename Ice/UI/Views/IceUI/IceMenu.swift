//
//  IceMenu.swift
//  Ice
//

import SwiftUI
import OSLog

struct IceMenu<Title: View, Label: View, Content: View>: View {
    @State private var isHovering = false

    private let title: Title
    private let label: Label
    private let content: Content

    /// Creates a menu with the given content, title, and label.
    ///
    /// - Parameters:
    ///   - content: A group of menu items.
    ///   - title: A view to display inside the menu.
    ///   - label: A view to display as an external label for the menu.
    init(
        @ViewBuilder content: () -> Content,
        @ViewBuilder title: () -> Title,
        @ViewBuilder label: () -> Label
    ) {
        self.title = title()
        self.label = label()
        self.content = content()
    }

    /// Creates a menu with the given content, title, and label key.
    ///
    /// - Parameters:
    ///   - labelKey: A string key for the menu's external label.
    ///   - content: A group of menu items.
    ///   - title: A view to display inside the menu.
    init(
        _ labelKey: LocalizedStringKey,
        @ViewBuilder content: () -> Content,
        @ViewBuilder title: () -> Title
    ) where Label == Text {
        self.init {
            content()
        } title: {
            title()
        } label: {
            Text(labelKey)
        }
    }

    var body: some View {
        IceLabeledContent {
            ZStack(alignment: .trailing) {
                IceMenuButton()
                    .allowsHitTesting(false)
                    .opacity(isHovering ? 1 : 0)

                _VariadicView.Tree(IceMenuLayout(title: title)) {
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

    func body(children: _VariadicView.Children) -> some View {
        Menu {
            ForEach(children) { child in
                IceMenuItem(child: child)
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

private class IceMenuItemAction: Hashable {
    static let nullAction = IceMenuItemAction {
        Logger.iceMenu.warning("No action assigned to menu item")
    }

    let body: () -> Void

    init(body: @escaping () -> Void) {
        self.body = body
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }

    static func == (lhs: IceMenuItemAction, rhs: IceMenuItemAction) -> Bool {
        ObjectIdentifier(lhs) == ObjectIdentifier(rhs)
    }
}

private struct IceMenuItemActionKey: PreferenceKey {
    static let defaultValue = IceMenuItemAction.nullAction

    static func reduce(value: inout IceMenuItemAction, nextValue: () -> IceMenuItemAction) {
        value = nextValue()
    }
}

private struct IceMenuItem: View {
    @State private var action = IceMenuItemAction.nullAction

    let child: _VariadicView.Children.Element

    var body: some View {
        Button {
            action.body()
        } label: {
            child
        }
        .onPreferenceChange(IceMenuItemActionKey.self) { action in
            self.action = action
        }
    }
}

extension View {
    /// Adds an action to perform when this view is clicked inside an ``IceMenu``.
    ///
    /// - Parameter action: An action to perform.
    func iceMenuItemAction(_ action: @escaping () -> Void) -> some View {
        preference(key: IceMenuItemActionKey.self, value: IceMenuItemAction(body: action))
    }
}

private extension Logger {
    static let iceMenu = Logger(category: "IceMenu")
}
