//
//  PressActions.swift
//  Ice
//

import SwiftUI

private struct ContinuousPress: ViewModifier {
    @State private var frame = CGRect.zero

    let coordinateSpace: CoordinateSpace
    let onChanged: (CGRect, CGPoint) -> Void
    let onEnded: (CGRect, CGPoint) -> Void

    func body(content: Content) -> some View {
        content
            .simultaneousGesture(
                DragGesture(minimumDistance: 0, coordinateSpace: coordinateSpace)
                    .onChanged { value in
                        onChanged(frame, value.location)
                    }
                    .onEnded { value in
                        onEnded(frame, value.location)
                    }
            )
            .onFrameChange(in: coordinateSpace, update: $frame)
    }
}

struct ContinuousPressInfo {
    let frame: CGRect
    let location: CGPoint

    fileprivate init(frame: CGRect, location: CGPoint) {
        self.frame = frame
        self.location = location
    }
}

extension View {
    func onContinuousPress(
        in coordinateSpace: CoordinateSpace = .local,
        onChanged: @escaping (ContinuousPressInfo) -> Void,
        onEnded: @escaping (ContinuousPressInfo) -> Void
    ) -> some View {
        modifier(
            ContinuousPress(
                coordinateSpace: coordinateSpace,
                onChanged: { frame, location in
                    onChanged(ContinuousPressInfo(frame: frame, location: location))
                },
                onEnded: { frame, location in
                    onEnded(ContinuousPressInfo(frame: frame, location: location))
                }
            )
        )
    }
}
