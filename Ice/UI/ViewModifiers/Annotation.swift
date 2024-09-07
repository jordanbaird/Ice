//
//  Annotation.swift
//  Ice
//

import SwiftUI

extension View {
    /// Adds the given view as an annotation below this view.
    ///
    /// - Parameters:
    ///   - alignment: The guide for aligning the annotation content horizontally with this view.
    ///   - spacing: The vertical spacing between this view and the annotation content.
    ///   - font: The font to apply to the annotation content's environment.
    ///   - foregroundStyle: The foreground style to apply to the annotation content's environment.
    ///   - content: A view builder that creates the annotation content.
    func annotation<Content: View, S: ShapeStyle>(
        alignment: HorizontalAlignment = .leading,
        spacing: CGFloat = 0,
        font: Font? = .subheadline,
        foregroundStyle: S = .secondary,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: alignment, spacing: spacing) {
            self
            content()
                .font(font)
                .foregroundStyle(foregroundStyle)
        }
    }

    /// Adds the given text as an annotation below this view.
    /// - Parameters:
    ///   - titleKey: The string key to add as an annotation.
    ///   - alignment: The guide for aligning the annotation content horizontally with this view.
    ///   - spacing: The vertical spacing between this view and the annotation content.
    ///   - font: The font to apply to the annotation content's environment.
    ///   - foregroundStyle: The foreground style to apply to the annotation content's environment.
    func annotation<S: ShapeStyle>(
        _ titleKey: LocalizedStringKey,
        alignment: HorizontalAlignment = .leading,
        spacing: CGFloat = 0,
        font: Font? = .subheadline,
        foregroundStyle: S = .secondary
    ) -> some View {
        annotation(
            alignment: alignment,
            spacing: spacing,
            font: font,
            foregroundStyle: foregroundStyle
        ) {
            Text(titleKey)
        }
    }
}
