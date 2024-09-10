//
//  IceForm.swift
//  Ice
//

import SwiftUI

struct IceForm<Content: View>: View {
    private let alignment: HorizontalAlignment
    private let padding: CGFloat
    private let spacing: CGFloat
    private let content: Content

    init(
        alignment: HorizontalAlignment = .center,
        padding: CGFloat = 20,
        spacing: CGFloat = 10,
        @ViewBuilder content: () -> Content
    ) {
        self.alignment = alignment
        self.padding = padding
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: alignment, spacing: spacing) {
                content
            }
            .padding(padding)
        }
        .scrollContentBackground(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        .toggleStyle(IceFormToggleStyle())
    }
}

private struct IceFormToggleStyle: ToggleStyle {
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
