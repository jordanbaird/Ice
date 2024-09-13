//
//  IceLabeledContent.swift
//  Ice
//

import SwiftUI

struct IceLabeledContent<Label: View, Content: View>: View {
    private let label: Label
    private let content: Content

    init(
        @ViewBuilder content: () -> Content,
        @ViewBuilder label: () -> Label
    ) {
        self.label = label()
        self.content = content()
    }

    init(
        _ titleKey: LocalizedStringKey,
        @ViewBuilder content: () -> Content
    ) where Label == Text {
        self.init {
            content()
        } label: {
            Text(titleKey)
        }
    }

    var body: some View {
        LabeledContent {
            content
                .layoutPriority(1)
        } label: {
            label
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(0)
        }
    }
}
