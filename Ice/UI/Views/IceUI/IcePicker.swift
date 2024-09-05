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
            _VariadicView.Tree(
                IcePickerLayout(selection: $selection) {
                    label
                }
            ) {
                content
            }
        } label: {
            label
        }
    }
}

private struct IcePickerLayout<Label: View, SelectionValue: Hashable>: _VariadicView_UnaryViewRoot {
    @Binding var selection: SelectionValue
    @State private var isHovering = false

    let label: Label

    init(selection: Binding<SelectionValue>, @ViewBuilder label: () -> Label) {
        self._selection = selection
        self.label = label()
    }

    @ViewBuilder
    func body(children: _VariadicView.Children) -> some View {
        ZStack(alignment: .trailing) {
            HStack(spacing: 4) {
                if let child = children.first(where: { $0.id() == selection }) {
                    child
                }
                ZStack {
                    if !isHovering {
                        RoundedRectangle(cornerRadius: 4, style: .circular)
                            .fill(.quaternary)
                            .aspectRatio(contentMode: .fill)
                    }
                    Image(systemName: "chevron.up.chevron.down")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(3)
                        .fontWeight(.bold)
                }
                .frame(width: 16, height: 16)
            }
            .padding(.horizontal, 2)
            .padding(.leading, 10)

            Picker(selection: $selection) {
                children
            } label: {
                label
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .opacity(isHovering ? 1 : 0)
            .menuIndicator(.hidden)
        }
        .onHover { hovering in
            isHovering = hovering
        }
        .fixedSize()
    }
}

#Preview {
    VStack {
        IcePicker(selection: .constant(0)) {
            ForEach(0...10, id: \.self) { i in
                Text(i.formatted())
            }
        } label: {
            Text("Ice Picker")
        }
        .padding()
    }
}
