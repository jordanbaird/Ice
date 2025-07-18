//
//  IceGroupBox.swift
//  Ice
//

import SwiftUI

struct IceGroupBox<Header: View, Content: View, Footer: View>: View {
    private let header: Header
    private let content: Content
    private let footer: Footer
    private let padding: EdgeInsets

    private var backgroundShape: some InsettableShape {
        if #available(macOS 26.0, *) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
        } else {
            RoundedRectangle(cornerRadius: 7, style: .circular)
        }
    }

    init(
        padding: EdgeInsets = .iceGroupBoxDefaultPadding,
        @ViewBuilder header: () -> Header,
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer
    ) {
        self.padding = padding
        self.header = header()
        self.content = content()
        self.footer = footer()
    }

    init(
        padding: CGFloat,
        @ViewBuilder header: () -> Header,
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer
    ) {
        self.init(padding: EdgeInsets(all: padding)) {
            header()
        } content: {
            content()
        } footer: {
            footer()
        }
    }

    init(
        padding: EdgeInsets = .iceGroupBoxDefaultPadding,
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer
    ) where Header == EmptyView {
        self.init(padding: padding) {
            EmptyView()
        } content: {
            content()
        } footer: {
            footer()
        }
    }

    init(
        padding: CGFloat,
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer
    ) where Header == EmptyView {
        self.init(padding: padding) {
            EmptyView()
        } content: {
            content()
        } footer: {
            footer()
        }
    }

    init(
        padding: EdgeInsets = .iceGroupBoxDefaultPadding,
        @ViewBuilder header: () -> Header,
        @ViewBuilder content: () -> Content
    ) where Footer == EmptyView {
        self.init(padding: padding) {
            header()
        } content: {
            content()
        } footer: {
            EmptyView()
        }
    }

    init(
        padding: CGFloat,
        @ViewBuilder header: () -> Header,
        @ViewBuilder content: () -> Content
    ) where Footer == EmptyView {
        self.init(padding: padding) {
            header()
        } content: {
            content()
        } footer: {
            EmptyView()
        }
    }

    init(
        padding: EdgeInsets = .iceGroupBoxDefaultPadding,
        @ViewBuilder content: () -> Content
    ) where Header == EmptyView, Footer == EmptyView {
        self.init(padding: padding) {
            EmptyView()
        } content: {
            content()
        } footer: {
            EmptyView()
        }
    }

    init(
        padding: CGFloat,
        @ViewBuilder content: () -> Content
    ) where Header == EmptyView, Footer == EmptyView {
        self.init(padding: padding) {
            EmptyView()
        } content: {
            content()
        } footer: {
            EmptyView()
        }
    }

    init(
        _ title: LocalizedStringKey,
        padding: EdgeInsets = .iceGroupBoxDefaultPadding,
        @ViewBuilder content: () -> Content
    ) where Header == Text, Footer == EmptyView {
        self.init(padding: padding) {
            Text(title)
                .font(.headline)
        } content: {
            content()
        }
    }

    init(
        _ title: LocalizedStringKey,
        padding: CGFloat,
        @ViewBuilder content: () -> Content
    ) where Header == Text, Footer == EmptyView {
        self.init(padding: padding) {
            Text(title)
                .font(.headline)
        } content: {
            content()
        }
    }

    var body: some View {
        VStack(alignment: .leading) {
            header
                .padding(.top, 8)
                .padding(.bottom, 2)
                .padding(.leading, 8)

            contentStack
                .padding(padding)
                .background {
                    backgroundShape
                        .fill(.quinary.opacity(0.67))
                        .strokeBorder(.quaternary)
                }
                .containerShape(backgroundShape)

            footer
                .padding(.top, 2)
                .padding(.bottom, 8)
                .padding(.leading, 8)
        }
    }

    @ViewBuilder
    private var contentStack: some View {
        VStack { content }
    }
}

extension EdgeInsets {
    /// The default padding for an ``IceGroupBox``.
    static let iceGroupBoxDefaultPadding = EdgeInsets(all: 12)
}
