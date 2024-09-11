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
            ZStack(alignment: .trailing) {
                IcePickerButton()
                    .allowsHitTesting(false)
                    .opacity(isHovering ? 1 : 0)

                Picker(selection: $selection) {
                    content
                        .labelStyle(.titleAndIcon)
                } label: {
                    label
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .buttonStyle(.plain)
                .menuIndicator(.visible)
                .baselineOffset(1)
                .padding(.leading, 5)
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

private struct IcePickerButton: NSViewRepresentable {
    func makeNSView(context: Context) -> NSButton {
        let button = NSButton()
        button.title = ""
        return button
    }

    func updateNSView(_ nsView: NSButton, context: Context) { }
}
