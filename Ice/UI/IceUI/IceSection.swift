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
    private var isBordered = true
    private var hasDividers = true

    init(
        @ViewBuilder header: () -> Header,
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer
    ) {
        self.header = header()
        self.content = content()
        self.footer = footer()
    }

    init(
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer
    ) where Header == EmptyView {
        self.init {
            EmptyView()
        } content: {
            content()
        } footer: {
            footer()
        }
    }

    init(
        @ViewBuilder header: () -> Header,
        @ViewBuilder content: () -> Content
    ) where Footer == EmptyView {
        self.init {
            header()
        } content: {
            content()
        } footer: {
            EmptyView()
        }
    }

    init(
        @ViewBuilder content: () -> Content
    ) where Header == EmptyView, Footer == EmptyView {
        self.init {
            EmptyView()
        } content: {
            content()
        } footer: {
            EmptyView()
        }
    }

    init(
        _ title: LocalizedStringKey,
        @ViewBuilder content: () -> Content
    ) where Header == Text, Footer == EmptyView {
        self.init {
            Text(title)
                .font(.headline)
        } content: {
            content()
        }
    }

    var body: some View {
        if isBordered {
            IceGroupBox(padding: spacing) {
                header
            } content: {
                dividedContent
            } footer: {
                footer
            }
        } else {
            VStack(alignment: .leading) {
                header
                dividedContent
                footer
            }
        }
    }

    @ViewBuilder
    private var dividedContent: some View {
        if hasDividers {
            _VariadicView.Tree(IceSectionLayout(spacing: spacing)) {
                content
                    .frame(maxWidth: .infinity)
            }
        } else {
            content
                .frame(maxWidth: .infinity)
        }
    }
}

extension IceSection {
    func bordered(_ isBordered: Bool = true) -> IceSection {
        with(self) { copy in
            copy.isBordered = isBordered
        }
    }

    func dividers(_ hasDividers: Bool = true) -> IceSection {
        with(self) { copy in
            copy.hasDividers = hasDividers
        }
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
                if child.id != last {
                    Divider()
                }
            }
        }
    }
}
