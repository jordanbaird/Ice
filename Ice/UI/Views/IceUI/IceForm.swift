//
//  IceForm.swift
//  Ice
//

import SwiftUI

struct IceForm<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                content
            }
            .padding(20)
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
