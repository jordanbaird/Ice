//
//  IceLabeledContent.swift
//  Ice
//

import SwiftUI

struct IceLabeledContent<Label: View, Content: View>: View {
    let label: Label
    let content: Content

    init(@ViewBuilder content: () -> Content, @ViewBuilder label: () -> Label) {
        self.label = label()
        self.content = content()
    }

    init(_ titleKey: LocalizedStringKey, @ViewBuilder content: () -> Content) where Label == Text {
        self.init {
            content()
        } label: {
            Text(titleKey)
        }
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            VStack(alignment: .leading) {
                label
            }
            Spacer()
            content
        }
    }
}
