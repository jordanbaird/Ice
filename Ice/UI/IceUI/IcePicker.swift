//
//  IcePicker.swift
//  Ice
//

import SwiftUI

struct IcePicker<Label: View, SelectionValue: Hashable, Content: View>: View {
    @Binding var selection: SelectionValue
    @State private var isHovering = false

    let label: Label
    let content: Content

    init(
        selection: Binding<SelectionValue>,
        @ViewBuilder content: () -> Content,
        @ViewBuilder label: () -> Label
    ) {
        self._selection = selection
        self.label = label()
        self.content = content()
    }

    init(
        _ titleKey: LocalizedStringKey,
        selection: Binding<SelectionValue>,
        @ViewBuilder content: () -> Content
    ) where Label == Text {
        self.init(selection: selection) {
            content()
        } label: {
            Text(titleKey)
        }
    }

    var body: some View {
        IceLabeledContent {
            ZStack {
                IcePickerButtonView()
                    .opacity(isHovering ? 1 : 0)
                    .allowsHitTesting(false)

                Picker(selection: $selection) {
                    content
                        .labelStyle(.titleAndIcon)
                } label: {
                    label
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .blendMode(.destinationOver)

                HStack(spacing: 5) {
                    _VariadicView.Tree(IcePickerLayout(selection: $selection)) {
                        content
                            .labelStyle(.titleAndIcon)
                    }
                    .offset(y: -0.5)

                    IcePopUpIndicator(isHovering: isHovering, isBordered: true, style: .popUp)
                }
                .allowsHitTesting(false)
                .padding(.trailing, 2)
                .padding(.leading, 10)
            }
            .fixedSize()
            .onHover { hovering in
                isHovering = hovering
            }
        } label: {
            label
        }
    }
}

private struct IcePickerButtonView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSButton {
        let button = NSButton()
        button.title = ""
        return button
    }

    func updateNSView(_ nsView: NSButton, context: Context) { }
}

private struct IcePickerLayout<SelectionValue: Hashable>: _VariadicView_UnaryViewRoot {
    @Binding var selection: SelectionValue

    @ViewBuilder
    func body(children: _VariadicView.Children) -> some View {
        if let child = children.first(where: { $0.id() == selection }) {
            child
        }
    }
}

extension View {
    /// Binds the identity of an item in an ``IcePicker`` to the given value.
    ///
    /// - Parameter id: A `Hashable` value to use as the view's identity.
    func icePickerID<ID: Hashable>(_ id: ID) -> some View {
        tag(id).id(id)
    }
}
