//
//  LayoutBarScrollView.swift
//  Ice
//

import Cocoa

class LayoutBarScrollView: NSScrollView {
    private let paddingView: LayoutBarPaddingView

    /// The amount of space between each arranged view.
    var spacing: CGFloat {
        get { paddingView.spacing }
        set { paddingView.spacing = newValue }
    }

    /// The layout view's arranged views.
    ///
    /// The views are laid out from left to right in the order that they appear in
    /// the array. The ``spacing`` property determines the amount of space between
    /// each view.
    var arrangedViews: [LayoutBarItemView] {
        get { paddingView.arrangedViews }
        set { paddingView.arrangedViews = newValue }
    }

    /// Creates a layout bar scroll view with the given menu bar manager, section
    /// and spacing.
    ///
    /// - Parameters:
    ///   - itemManager: The shared menu bar item manager instance.
    ///   - section: The section whose items are represented.
    ///   - spacing: The amount of space between each arranged view.
    init(itemManager: MenuBarItemManager, section: MenuBarSection, spacing: CGFloat) {
        self.paddingView = LayoutBarPaddingView(itemManager: itemManager, section: section, spacing: spacing)

        super.init(frame: .zero)

        self.hasHorizontalScroller = true
        self.horizontalScroller = HorizontalScroller()

        self.verticalScrollElasticity = .none
        self.horizontalScrollElasticity = .none

        self.drawsBackground = false

        self.documentView = self.paddingView

        self.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            // constrain the height to a constant
            heightAnchor.constraint(equalToConstant: 50),

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
    /// A custom scroller that overrides its knob slot to be transparent.
    class HorizontalScroller: NSScroller {
        override class var isCompatibleWithOverlayScrollers: Bool { true }

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            self.controlSize = .mini
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) { }
    }
}
