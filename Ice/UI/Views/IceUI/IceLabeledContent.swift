//
//  IceLabeledContent.swift
//  Ice
//

import SwiftUI

struct IceLabeledContent<Label: View, Content: View>: View {
    let spacing: CGFloat?
    let label: Label
    let content: Content

    init(spacing: CGFloat? = nil, @ViewBuilder content: () -> Content, @ViewBuilder label: () -> Label) {
        self.spacing = spacing
        self.label = label()
        self.content = content()
    }

    init(_ titleKey: LocalizedStringKey, spacing: CGFloat? = nil, @ViewBuilder content: () -> Content) where Label == Text {
        self.init(spacing: spacing) {
            content()
        } label: {
            Text(titleKey)
        }
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: spacing) {
            // Place label in VStack so that multiple views are laid out vertically.
            VStack(alignment: .leading) {
                label
            }
            Spacer()
            content
        }
    }
}
