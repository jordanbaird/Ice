//
//  AnnotationView.swift
//  Ice
//

import SwiftUI

/// A view that displays content as an annotation below a parent view.
struct AnnotationView<Parent: View, Content: View, ForegroundStyle: ShapeStyle>: View {
    let alignment: HorizontalAlignment
    let spacing: CGFloat
    let font: Font?
    let foregroundStyle: ForegroundStyle
    let parent: Parent
    let content: Content

    init(
        alignment: HorizontalAlignment = .leading,
        spacing: CGFloat = 0,
        font: Font? = .subheadline,
        foregroundStyle: ForegroundStyle = .secondary,
        @ViewBuilder parent: () -> Parent,
        @ViewBuilder content: () -> Content
    ) {
        self.alignment = alignment
        self.spacing = spacing
        self.font = font
        self.foregroundStyle = foregroundStyle
        self.parent = parent()
        self.content = content()
    }

    init(
        _ titleKey: LocalizedStringKey,
        alignment: HorizontalAlignment = .leading,
        spacing: CGFloat = 0,
        font: Font? = .subheadline,
        foregroundStyle: ForegroundStyle = .secondary,
        @ViewBuilder parent: () -> Parent
    ) where Content == Text {
        self.init(
            alignment: alignment,
            spacing: spacing,
            font: font,
            foregroundStyle: foregroundStyle
        ) {
            parent()
        } content: {
            Text(titleKey)
        }
    }

    init(
        alignment: HorizontalAlignment = .leading,
        spacing: CGFloat = 0,
        font: Font? = .subheadline,
        foregroundStyle: ForegroundStyle = .secondary,
        @ViewBuilder content: () -> Content
    ) where Parent == EmptyView {
        self.init(
            alignment: alignment,
            spacing: spacing,
            font: font,
            foregroundStyle: foregroundStyle
        ) {
            EmptyView()
        } content: {
            content()
        }
    }

    init(
        _ titleKey: LocalizedStringKey,
        alignment: HorizontalAlignment = .leading,
        spacing: CGFloat = 0,
        font: Font? = .subheadline,
        foregroundStyle: ForegroundStyle = .secondary
    ) where Parent == EmptyView, Content == Text {
        self.init(
            titleKey,
            alignment: alignment,
            spacing: spacing,
            font: font,
            foregroundStyle: foregroundStyle
        ) {
            EmptyView()
        }
    }

    var body: some View {
        VStack(alignment: alignment, spacing: spacing) {
            parent
            content
                .font(font)
                .foregroundStyle(foregroundStyle)
        }
    }
}

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
        AnnotationView(
            alignment: alignment,
            spacing: spacing,
            font: font,
            foregroundStyle: foregroundStyle
        ) {
            self
        } content: {
            content()
        }
    }

    /// Adds the given text as an annotation below this view.
    ///
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
        AnnotationView(
            titleKey,
            alignment: alignment,
            spacing: spacing,
            font: font,
            foregroundStyle: foregroundStyle
        ) {
            self
        }
    }
}
