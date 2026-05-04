//
//  IceForm.swift
//  Ice
//

import SwiftUI

struct IceForm<Content: View>: View {
    @State private var contentFrame = CGRect.zero

    private let alignment: HorizontalAlignment
    private let padding: EdgeInsets
    private let spacing: CGFloat
    private let content: Content

    init(
        alignment: HorizontalAlignment = .center,
        padding: EdgeInsets = .iceFormDefaultPadding,
        spacing: CGFloat = .iceFormDefaultSpacing,
        @ViewBuilder content: () -> Content
    ) {
        self.alignment = alignment
        self.padding = padding
        self.spacing = spacing
        self.content = content()
    }

    init(
        alignment: HorizontalAlignment = .center,
        padding: CGFloat,
        spacing: CGFloat = .iceFormDefaultSpacing,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            alignment: alignment,
            padding: EdgeInsets(all: padding),
            spacing: spacing
        ) {
            content()
        }
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                contentLayout.frame(
                    maxWidth: geometry.size.width,
                    minHeight: geometry.size.height,
                    alignment: .top
                )
            }
            .scrollContentBackground(.hidden)
            .scrollIndicatorsFlash(onAppear: true)
            .scrollDisabled(contentFrame.height > 0 && contentFrame.height <= geometry.size.height)
        }
        .focusSection()
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var contentLayout: some View {
        VStack(alignment: alignment, spacing: spacing) {
            content
                .labeledContentStyle(IceFormLabeledContentStyle())
                .toggleStyle(IceFormToggleStyle())
        }
        .padding(padding)
        .onFrameChange(update: $contentFrame)
    }
}

private struct IceFormLabeledContentStyle: LabeledContentStyle {
    func makeBody(configuration: Configuration) -> some View {
        LabeledContent {
            configuration.content
                .layoutPriority(1)
        } label: {
            configuration.label
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(0)
        }
    }
}

private struct IceFormToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Toggle(configuration)
            .toggleStyle(.switch)
            .controlSize(.mini)
    }
}

extension EdgeInsets {
    /// The default padding for an ``IceForm``.
    static let iceFormDefaultPadding: EdgeInsets = {
        var insets = EdgeInsets(all: 20)
        if #available(macOS 26.0, *) {
            insets.top = 0
        }
        return insets
    }()
}

extension CGFloat {
    /// The default spacing for an ``IceForm``.
    static let iceFormDefaultSpacing: CGFloat = 10
}
