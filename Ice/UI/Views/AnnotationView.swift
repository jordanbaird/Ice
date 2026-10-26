//
//  AnnotationView.swift
//  Ice
//

import SwiftUI

/// A view that displays content as an annotation below a parent view.
struct AnnotationView<Parent: View, Content: View, ForegroundStyle: ShapeStyle>: View {
    private let alignment: HorizontalAlignment
    private let spacing: CGFloat
    private let font: Font?
    private let foregroundStyle: ForegroundStyle
    private let parent: Parent
    private let content: Content

    /// Creates an annotation view with a parent and content view.
    ///
    /// - Parameters:
    ///   - alignment: The alignment of the content view in relation to the parent view.
    ///   - spacing: The spacing between the parent and content view.
    ///   - font: The font to apply to the content view's environment.
    ///   - foregroundStyle: The foreground style to apply to the content view's environment.
    ///   - parent: The parent view of the annotation.
    ///   - content: The content view of the annotation.
    init(
        alignment: HorizontalAlignment = .leading,
        spacing: CGFloat = .annotationDefaultSpacing,
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

    /// Creates an annotation view with a string key and parent view.
    ///
    /// - Parameters:
    ///   - titleKey: The string key to display as text below the parent view.
    ///   - alignment: The alignment of the content view in relation to the parent view.
    ///   - spacing: The spacing between the parent and content view.
    ///   - font: The font to apply to the content view's environment.
    ///   - foregroundStyle: The foreground style to apply to the content view's environment.
    ///   - parent: The parent view of the annotation.
    init(
        _ titleKey: LocalizedStringKey,
        alignment: HorizontalAlignment = .leading,
        spacing: CGFloat = .annotationDefaultSpacing,
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

    /// Creates an annotation view with a content view.
    ///
    /// - Parameters:
    ///   - alignment: The alignment of the content view in relation to the parent view.
    ///   - spacing: The spacing between the parent and content view.
    ///   - font: The font to apply to the content view's environment.
    ///   - foregroundStyle: The foreground style to apply to the content view's environment.
    ///   - content: The content view of the annotation.
    init(
        alignment: HorizontalAlignment = .leading,
        spacing: CGFloat = .annotationDefaultSpacing,
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

    /// Creates an annotation view with a string key.
    ///
    /// - Parameters:
    ///   - titleKey: The string key to display as text.
    ///   - alignment: The alignment of the content view in relation to the parent view.
    ///   - spacing: The spacing between the parent and content view.
    ///   - font: The font to apply to the content view's environment.
    ///   - foregroundStyle: The foreground style to apply to the content view's environment.
    init(
        _ titleKey: LocalizedStringKey,
        alignment: HorizontalAlignment = .leading,
        spacing: CGFloat = .annotationDefaultSpacing,
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
        .frame(maxWidth: .infinity, alignment: Alignment(horizontal: alignment, vertical: .center))
        .fixedSize(horizontal: false, vertical: true)
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
    func annotation<Content: View, ForegroundStyle: ShapeStyle>(
        alignment: HorizontalAlignment = .leading,
        spacing: CGFloat = .annotationDefaultSpacing,
        font: Font? = .subheadline,
        foregroundStyle: ForegroundStyle = .secondary,
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
    ///   - titleKey: The string key to display as text below this view.
    ///   - alignment: The guide for aligning the annotation content horizontally with this view.
    ///   - spacing: The vertical spacing between this view and the annotation content.
    ///   - font: The font to apply to the annotation content's environment.
    ///   - foregroundStyle: The foreground style to apply to the annotation content's environment.
    func annotation<ForegroundStyle: ShapeStyle>(
        _ titleKey: LocalizedStringKey,
        alignment: HorizontalAlignment = .leading,
        spacing: CGFloat = .annotationDefaultSpacing,
        font: Font? = .subheadline,
        foregroundStyle: ForegroundStyle = .secondary
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

extension CGFloat {
    /// The default spacing for an ``IceForm``.
    static let annotationDefaultSpacing: CGFloat = 2
}
