//
//  IceSection.swift
//  Ice
//

import SwiftUI

struct IceSection<Header: View, Content: View, Footer: View>: View {
    private let header: Header
    private let content: Content
    private let footer: Footer
    private let spacing: CGFloat = 10

    init(@ViewBuilder header: () -> Header, @ViewBuilder content: () -> Content, @ViewBuilder footer: () -> Footer) {
        self.header = header()
        self.content = content()
        self.footer = footer()
    }

    init(@ViewBuilder content: () -> Content, @ViewBuilder footer: () -> Footer) where Header == EmptyView {
        self.init {
            EmptyView()
        } content: {
            content()
        } footer: {
            footer()
        }
    }

    init(@ViewBuilder header: () -> Header, @ViewBuilder content: () -> Content) where Footer == EmptyView {
        self.init {
            header()
        } content: {
            content()
        } footer: {
            EmptyView()
        }
    }

    init(@ViewBuilder content: () -> Content) where Header == EmptyView, Footer == EmptyView {
        self.init {
            EmptyView()
        } content: {
            content()
        } footer: {
            EmptyView()
        }
    }

    init(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) where Header == Text, Footer == EmptyView {
        self.init {
            Text(title)
                .font(.headline)
        } content: {
            content()
        }
    }

    var body: some View {
        VStack(alignment: .leading) {
            header
            _VariadicView.Tree(IceSectionLayout(spacing: spacing)) {
                content
                    .frame(maxWidth: .infinity)
            }
            .background {
                backgroundShape
                    .fill(.quinary)
                    .overlay {
                        backgroundShape
                            .stroke(.quaternary)
                    }
            }
            footer
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
