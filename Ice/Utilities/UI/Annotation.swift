//
//  Annotation.swift
//  Ice
//

import SwiftUI

private struct AnnotationModifier<Annotation: View>: ViewModifier {
    let alignment: HorizontalAlignment
    let spacing: CGFloat?
    let annotation: Annotation

    func body(content: Content) -> some View {
        VStack(alignment: alignment, spacing: spacing) {
            content
            annotation
                .foregroundColor(.secondary)
                .transformEnvironment(\.font) { font in
                    if font == nil {
                        font = .callout
                    }
                }
        }
    }
}

extension View {
    /// Adds the given view as an annotation below this view.
    ///
    /// - Parameters:
    ///   - alignment: The guide for aligning the annotation horizontally
    ///     with the view.
    ///   - spacing: The distance between the view and the annotation.
    ///     Pass `nil` to cause the system to use a default distance.
    ///   - content: A view builder that creates the annotation content.
    func annotation<Content: View>(
        alignment: HorizontalAlignment = .leading,
        spacing: CGFloat? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        modifier(
            AnnotationModifier(
                alignment: alignment,
                spacing: spacing,
                annotation: content()
            )
        )
    }
}
