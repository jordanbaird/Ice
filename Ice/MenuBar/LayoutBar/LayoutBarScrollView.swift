//
//  LayoutBarScrollView.swift
//  Ice
//

import Cocoa

final class LayoutBarScrollView: NSScrollView {
    private let paddingView: LayoutBarPaddingView

    /// The layout view's arranged views.
    ///
    /// The views are laid out from left to right in the order that they appear in
    /// the array. The ``spacing`` property determines the amount of space between
    /// each view.
    var arrangedViews: [LayoutBarItemView] {
        get { paddingView.arrangedViews }
        set { paddingView.arrangedViews = newValue }
    }

    /// Creates a layout bar scroll view with the given app state, section, and spacing.
    ///
    /// - Parameters:
    ///   - appState: The shared app state instance.
    ///   - section: The section whose items are represented.
    init(appState: AppState, section: MenuBarSection.Name) {
        self.paddingView = LayoutBarPaddingView(appState: appState, section: section)

        super.init(frame: .zero)

        self.hasHorizontalScroller = true
        self.horizontalScroller = HorizontalScroller()

        self.autohidesScrollers = true

        self.verticalScrollElasticity = .none

        self.drawsBackground = false

        self.documentView = self.paddingView

        self.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            // constrain the padding view's height to the content view's height
            paddingView.heightAnchor.constraint(equalTo: contentView.heightAnchor),

            // constrain the padding view's width to greater than or equal to the content
            // view's width
            paddingView.widthAnchor.constraint(greaterThanOrEqualTo: contentView.widthAnchor),

            // constrain the padding view's trailing anchor to the content view's trailing
            // anchor; this, in combination with the above width constraint, aligns the
            // items in the layout bar to the trailing edge
            paddingView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

extension LayoutBarScrollView {
    override func accessibilityChildren() -> [Any]? {
        return arrangedViews
    }
}

extension LayoutBarScrollView {
    /// A custom scroller that overrides its knob slot to be transparent.
    final class HorizontalScroller: NSScroller {
        override static var isCompatibleWithOverlayScrollers: Bool { true }

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            self.controlSize = .mini
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }
}
