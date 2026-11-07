//
//  CalloutBox.swift
//  Ice
//

import SwiftUI

struct CalloutBox<Content: View, Icon: View, ForegroundStyle: ShapeStyle>: View {
    private let content: Content
    private let icon: Icon
    private let alignment: HorizontalAlignment
    private let font: Font?
    private let foregroundStyle: ForegroundStyle

    private init(
        content: Content,
        icon: Icon,
        alignment: HorizontalAlignment,
        font: Font?,
        foregroundStyle: ForegroundStyle
    ) {
        self.content = content
        self.icon = icon
        self.alignment = alignment
        self.font = font
        self.foregroundStyle = foregroundStyle
    }

    init(
        alignment: HorizontalAlignment = .center,
        font: Font? = .calloutBox,
        foregroundStyle: ForegroundStyle = .secondary,
        @ViewBuilder content: () -> Content,
        @ViewBuilder icon: () -> Icon
    ) {
        self.init(
            content: content(),
            icon: icon(),
            alignment: alignment,
            font: font,
            foregroundStyle: foregroundStyle
        )
    }

    init(
        alignment: HorizontalAlignment = .center,
        font: Font? = .calloutBox,
        foregroundStyle: ForegroundStyle = .secondary,
        @ViewBuilder content: () -> Content
    ) where Icon == EmptyView {
        self.init(
            content: content(),
            icon: EmptyView(),
            alignment: alignment,
            font: font,
            foregroundStyle: foregroundStyle
        )
    }

    init(
        _ titleKey: LocalizedStringKey,
        alignment: HorizontalAlignment = .center,
        font: Font? = .calloutBox,
        foregroundStyle: ForegroundStyle = .secondary
    ) where Content == Text, Icon == EmptyView {
        self.init(
            content: Text(titleKey),
            icon: EmptyView(),
            alignment: alignment,
            font: font,
            foregroundStyle: foregroundStyle
        )
    }

    init(
        _ titleKey: LocalizedStringKey,
        alignment: HorizontalAlignment = .center,
        font: Font? = .calloutBox,
        foregroundStyle: ForegroundStyle = .secondary,
        @ViewBuilder icon: () -> Icon
    ) where Content == Text {
        self.init(
            content: Text(titleKey),
            icon: icon(),
            alignment: alignment,
            font: font,
            foregroundStyle: foregroundStyle
        )
    }

    init(
        systemImage: String,
        alignment: HorizontalAlignment = .center,
        font: Font? = .calloutBox,
        foregroundStyle: ForegroundStyle = .secondary,
        @ViewBuilder content: () -> Content
    ) where Icon == Image {
        self.init(
            content: content(),
            icon: Image(systemName: systemImage),
            alignment: alignment,
            font: font,
            foregroundStyle: foregroundStyle
        )
    }

    init(
        _ titleKey: LocalizedStringKey,
        systemImage: String,
        alignment: HorizontalAlignment = .center,
        font: Font? = .calloutBox,
        foregroundStyle: ForegroundStyle = .secondary
    ) where Content == Text, Icon == Image {
        self.init(
            content: Text(titleKey),
            icon: Image(systemName: systemImage),
            alignment: alignment,
            font: font,
            foregroundStyle: foregroundStyle
        )
    }

    var body: some View {
        IceGroupBox {
            Label {
                content
            } icon: {
                icon
            }
            .font(font)
            .foregroundStyle(foregroundStyle)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: Alignment(horizontal: alignment, vertical: .center))
        }
    }
}

extension Font {
    /// The default font for Ice callout boxes.
    static let calloutBox = callout.bold()
}
