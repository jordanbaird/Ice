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

        self.documentView = paddingView
        self.hasHorizontalScroller = true
        self.hasVerticalScroller = false
        self.verticalScrollElasticity = .none
        self.autohidesScrollers = true
        self.drawsBackground = false
        self.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            paddingView.heightAnchor.constraint(equalTo: contentView.heightAnchor),
            paddingView.widthAnchor.constraint(greaterThanOrEqualTo: contentView.widthAnchor),
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
