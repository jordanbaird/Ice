//
//  IceSection.swift
//  Ice
//

import SwiftUI

struct IceSection<Content: View>: View {
    private let spacing: CGFloat = 10

    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        _VariadicView.Tree(IceSectionLayout(spacing: spacing)) {
            content
                .toggleStyle(IceSectionToggleStyle())
        }
        .background {
            backgroundShape
                .fill(.quinary)
                .overlay {
                    backgroundShape
                        .stroke(.quaternary)
                }
        }
    }

    @ViewBuilder
    private var backgroundShape: some Shape {
        RoundedRectangle(cornerRadius: 7, style: .circular)
    }
}

private struct IceSectionLayout: _VariadicView_UnaryViewRoot {
    let spacing: CGFloat

    @ViewBuilder
    func body(children: _VariadicView.Children) -> some View {
        let last = children.last?.id
        VStack(alignment: .leading, spacing: spacing) {
            ForEach(children) { child in
                child
                    .mask(Rectangle())
                if child.id != last {
                    Divider()
                        .opacity(0.5)
                }
            }
        }
        .padding(spacing)
    }
}

private struct IceSectionToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        IceLabeledContent {
            Toggle(isOn: configuration.$isOn) {
                configuration.label
            }
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
        } label: {
            configuration.label
        }
    }
}

#Preview("IceSection") {
    IceSection {
        Text("Hello")
        Text("How")
        Text("Are")
        Text("You")
        Toggle("Toggle", isOn: .constant(true))
        IcePicker("Picker", selection: .constant(0)) {
            ForEach(0...10, id: \.self) { i in
                Text(i.formatted())
            }
        }
    }
    .padding()
    .frame(width: 500)
    .fixedSize()
}

#Preview("Grouped Form") {
    Form {
        Text("Hello")
        Text("How")
        Text("Are")
        Text("You")
        Toggle("Toggle", isOn: .constant(true))
        Picker("Picker", selection: .constant(0)) {
            ForEach(0...10, id: \.self) { i in
                Text(i.formatted())
            }
        }
    }
    .formStyle(.grouped)
    .frame(width: 500)
    .fixedSize()
}
