//
//  InterceptMouseDown.swift
//  Ice
//

import SwiftUI

/// A view that prevents mouse down events from being passed
/// up into its superviews.
struct InterceptMouseDown: View {
    private class MouseDownInterceptorView: NSView {
        var shouldIntercept = true
        override var mouseDownCanMoveWindow: Bool { !shouldIntercept }
    }

    private struct Representable: NSViewRepresentable {
        let shouldIntercept: Bool

        func makeNSView(context: Context) -> NSView {
            let view = MouseDownInterceptorView()
            view.shouldIntercept = shouldIntercept
            return view
        }

        func updateNSView(_: NSView, context: Context) { }
    }

    /// A Boolean value that indicates whether the view should
    /// prevent mouse down events from being passed up into its
    /// superviews.
    let shouldIntercept: Bool

    /// Creates a view that prevents mouse down events from being
    /// passed up into its superviews.
    ///
    /// - Parameter shouldIntercept: A Boolean value that indicates
    ///   whether the created view should prevent mouse down events
    ///   from being passed up into its superviews.
    init(_ shouldIntercept: Bool) {
        self.shouldIntercept = shouldIntercept
    }

    var body: some View {
        Representable(shouldIntercept: shouldIntercept)
    }
}

extension View {
    /// Sets whether to prevent mouse down events from being passed
    /// up into this view's superviews.
    ///
    /// - Warning: Applying this modifier does not cancel out previous
    ///   applications of the modifier. Instead, it is somewhat naively
    ///   applied at the current level, and is stacked atop any of the
    ///   modifier's previous occurrences.
    ///
    /// - Parameter shouldIntercept: A Boolean value that indicates
    ///   whether the view should prevent mouse down events from being
    ///   passed up into its superviews.
    ///
    /// - Returns: A view that prevents mouse down events from being
    ///   passed up into its superviews, based on the value passed to
    ///   `shouldIntercept`.
    func interceptMouseDown(_ shouldIntercept: Bool = true) -> some View {
        background {
            InterceptMouseDown(shouldIntercept)
        }
    }
}
