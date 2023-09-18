//
//  ContinuousPress.swift
//  Ice
//

import SwiftUI

/// Information accompanying a continuous press gesture.
struct ContinuousPressInfo {
    /// The frame of the view to which the gesture is applied.
    let frame: CGRect

    /// The current location of the drag or press, relative to
    /// the coordinate space of the gesture.
    let location: CGPoint

    /// The coordinate space used to create the gesture.
    let coordinateSpace: CoordinateSpace

    /// Creates an instance with the given frame, location,
    /// and coordinate space.
    fileprivate init(
        frame: CGRect,
        location: CGPoint,
        coordinateSpace: CoordinateSpace
    ) {
        self.frame = frame
        self.location = location
        self.coordinateSpace = coordinateSpace
    }
}

/// A view modifier that adds a continuous press gesture to a view.
private struct ContinuousPressModifier: ViewModifier {
    /// The view's frame.
    @State private var frame = CGRect.zero

    /// The coordinate space of the gesture.
    let coordinateSpace: CoordinateSpace

    /// A closure to perform when the gesture's value changes.
    let onChanged: (ContinuousPressInfo) -> Void

    /// A closure to perform when the gesture ends.
    let onEnded: (ContinuousPressInfo) -> Void

    func body(content: Content) -> some View {
        content
            .simultaneousGesture(
                DragGesture(minimumDistance: 0, coordinateSpace: coordinateSpace)
                    .onChanged { value in
                        call(onChanged, with: value.location)
                    }
                    .onEnded { value in
                        call(onEnded, with: value.location)
                    }
            )
            .onFrameChange(in: coordinateSpace, update: $frame)
    }

    /// Calls the given handler, using the specified location to
    /// construct its parameter.
    func call(_ handler: (ContinuousPressInfo) -> Void, with location: CGPoint) {
        let info = ContinuousPressInfo(
            frame: frame,
            location: location,
            coordinateSpace: coordinateSpace
        )
        handler(info)
    }
}

extension View {
    /// Adds a continuous press gesture to the view.
    ///
    /// A continuous press gesture is similar to a drag gesture with
    /// a minimum distance of `0`. The most important difference is
    /// the value passed into the `onChanged` and `onEnded` closures;
    /// it contains two fields -- the frame of the view, and the current
    /// location of the drag or press relative to the coordinate space
    /// passed to the `coordinateSpace` parameter.
    ///
    /// - Parameters:
    ///   - coordinateSpace: The coordinate space of the gesture.
    ///   - onChanged: A closure to perform when the gesture's value changes.
    ///   - onEnded: A closure to perform when the gesture ends.
    ///
    /// - Returns: A view that adds a continuous press gesture to the
    ///   current view.
    func onContinuousPress(
        in coordinateSpace: CoordinateSpace = .local,
        onChanged: @escaping (ContinuousPressInfo) -> Void,
        onEnded: @escaping (ContinuousPressInfo) -> Void
    ) -> some View {
        modifier(
            ContinuousPressModifier(
                coordinateSpace: coordinateSpace,
                onChanged: onChanged,
                onEnded: onEnded
            )
        )
    }
}
