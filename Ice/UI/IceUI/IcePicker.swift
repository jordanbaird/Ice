//
//  IcePicker.swift
//  Ice
//

import SwiftUI

struct IcePicker<Label: View, SelectionValue: Hashable, Content: View>: View {
    @Binding var selection: SelectionValue

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
            Picker(selection: $selection) {
                content
                    .labelStyle(.titleAndIcon)
                    .toggleStyle(.automatic)
            } label: {
                label
            }
            .pickerStyle(.menu)
            .buttonStyle(.plain)
            .tint(.primary)
            .font(.callout)
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .labelsHidden()
            .fixedSize()
        } label: {
            label
        }
    }
}
