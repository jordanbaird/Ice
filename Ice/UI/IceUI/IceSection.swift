//
//  IceSection.swift
//  Ice
//

import SwiftUI

struct IceSectionOptions: OptionSet {
    let rawValue: Int

    static let isBordered = IceSectionOptions(rawValue: 1 << 0)
    static let hasDividers = IceSectionOptions(rawValue: 1 << 1)

    static let plain: IceSectionOptions = []
    static let `default`: IceSectionOptions = [.isBordered, .hasDividers]
}

struct IceSection<Header: View, Content: View, Footer: View>: View {
    private let header: Header
    private let content: Content
    private let footer: Footer
    private let spacing: CGFloat
    private let options: IceSectionOptions

    private var isBordered: Bool { options.contains(.isBordered) }
    private var hasDividers: Bool { options.contains(.hasDividers) }

    init(
        spacing: CGFloat = .iceSectionDefaultSpacing,
        options: IceSectionOptions = .default,
        @ViewBuilder header: () -> Header,
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer
    ) {
        self.spacing = spacing
        self.options = options
        self.header = header()
        self.content = content()
        self.footer = footer()
    }

    init(
        spacing: CGFloat = .iceSectionDefaultSpacing,
        options: IceSectionOptions = .default,
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer
    ) where Header == EmptyView {
        self.init(spacing: spacing, options: options) {
            EmptyView()
        } content: {
            content()
        } footer: {
            footer()
        }
    }

    init(
        spacing: CGFloat = .iceSectionDefaultSpacing,
        options: IceSectionOptions = .default,
        @ViewBuilder header: () -> Header,
        @ViewBuilder content: () -> Content
    ) where Footer == EmptyView {
        self.init(spacing: spacing, options: options) {
            header()
        } content: {
            content()
        } footer: {
            EmptyView()
        }
    }

    init(
        spacing: CGFloat = .iceSectionDefaultSpacing,
        options: IceSectionOptions = .default,
        @ViewBuilder content: () -> Content
    ) where Header == EmptyView, Footer == EmptyView {
        self.init(spacing: spacing, options: options) {
            EmptyView()
        } content: {
            content()
        } footer: {
            EmptyView()
        }
    }

    init(
        _ title: LocalizedStringKey,
        spacing: CGFloat = .iceSectionDefaultSpacing,
        options: IceSectionOptions = .default,
        @ViewBuilder content: () -> Content
    ) where Header == Text, Footer == EmptyView {
        self.init(spacing: spacing, options: options) {
            Text(title).font(.headline)
        } content: {
            content()
        }
    }

    var body: some View {
        Section {
            if isBordered {
                IceGroupBox {
                    header
                } content: {
                    contentLayout
                } footer: {
                    footer
                }
            } else {
                VStack(alignment: .leading) {
                    header
                        .accessibilityAddTraits(.isHeader)
                        .padding([.top, .leading], 8)
                        .padding(.bottom, 2)

                    contentLayout

                    footer
                        .padding([.bottom, .leading], 8)
                        .padding(.top, 2)
                }
                .focusSection()
                .accessibilityElement(children: .contain)
            }
        }
        .focusSection()
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var contentLayout: some View {
        if hasDividers {
            _VariadicView.Tree(IceSectionLayout(spacing: spacing)) {
                content.frame(maxWidth: .infinity)
            }
        } else {
            content.frame(maxWidth: .infinity)
        }
    }
}

// MARK: - IceSectionLayout

private struct IceSectionLayout: _VariadicView_UnaryViewRoot {
    let spacing: CGFloat

    @ViewBuilder
    func body(children: _VariadicView.Children) -> some View {
        let last = children.last?.id
        VStack(alignment: .leading, spacing: spacing) {
            ForEach(children) { child in
                child
                if child.id != last {
                    IceSectionDivider()
                }
            }
        }
    }
}

// MARK: - IceSectionDivider

private struct IceSectionDivider: View {
    var body: some View {
        if #available(macOS 26.0, *) {
            Rectangle()
                .fill(.separator.quinary)
                .frame(height: 1)
        } else {
            Divider()
        }
    }
}

extension CGFloat {
    /// The default spacing for an ``IceSection``.
    static let iceSectionDefaultSpacing: CGFloat = if #available(macOS 26.0, *) { 11 } else { 10 }
}
