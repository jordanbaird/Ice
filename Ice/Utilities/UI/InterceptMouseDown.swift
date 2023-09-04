//
//  InterceptMouseDown.swift
//  Ice
//

import SwiftUI

/// A view that prevents mouse down events from being passed
/// down to its superviews.
struct InterceptMouseDown: View {
    private class Represented: NSView {
        var shouldIntercept = true
        override var mouseDownCanMoveWindow: Bool { !shouldIntercept }
    }

    private struct Representable: NSViewRepresentable {
        let shouldIntercept: Bool

        func makeNSView(context: Context) -> NSView {
            let view = Represented()
            view.shouldIntercept = shouldIntercept
            return view
        }

        func updateNSView(_: NSView, context: Context) { }
    }

    /// A Boolean value that indicates whether the view should
    /// prevent mouse down events from being passed down to its
    /// superviews.
    let shouldIntercept: Bool

    /// Creates a view that prevents mouse down events from being
    /// passed down to its superviews.
    ///
    /// - Parameter shouldIntercept: A Boolean value that indicates
    ///   whether the created view should prevent mouse down events
    ///   from being passed down to its superviews.
    init(_ shouldIntercept: Bool) {
        self.shouldIntercept = shouldIntercept
    }

    var body: some View {
        Representable(shouldIntercept: shouldIntercept)
    }
}

extension View {
    /// Sets whether to prevent mouse down events from being passed
    /// down to this view's superviews.
    ///
    /// - Parameter shouldIntercept: A Boolean value that indicates
    ///   whether the view should prevent mouse down events from being
    ///   passed down to its superviews.
    ///
    /// - Returns: A view that prevents mouse down events from being
    ///   passed down to its superviews, based on the value passed to
    ///   `shouldIntercept`.
    func interceptMouseDown(_ shouldIntercept: Bool = true) -> some View {
        background(InterceptMouseDown(shouldIntercept))
    }
}
