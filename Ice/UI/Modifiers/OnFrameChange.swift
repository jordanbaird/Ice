//
//  OnFrameChange.swift
//  Ice
//

import SwiftUI

private struct FramePreferenceKey: PreferenceKey {
    static let defaultValue = CGRect.zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

extension View {
    /// Performs the given action when the view's frame changes.
    ///
    /// - Parameters:
    ///   - coordinateSpace: The coordinate space to use when accessing
    ///     the view's frame.
    ///   - action: An action to perform when the view's frame changes.
    ///     The closure takes the new frame as a parameter.
    func onFrameChange(
        in coordinateSpace: some CoordinateSpaceProtocol = .local,
        perform action: @escaping (CGRect) -> Void
    ) -> some View {
        background {
            GeometryReader { geometry in
                Color.clear
                    .preference(
                        key: FramePreferenceKey.self,
                        value: geometry.frame(in: coordinateSpace)
                    )
                    .onPreferenceChange(FramePreferenceKey.self, perform: action)
            }
        }
    }

    /// Updates the given binding when the view's frame changes.
    ///
    /// - Parameters:
    ///   - coordinateSpace: The coordinate space to use when accessing
    ///     the view's frame.
    ///   - binding: A binding to update when the view's frame changes.
    func onFrameChange(
        in coordinateSpace: some CoordinateSpaceProtocol = .local,
        update binding: Binding<CGRect>
    ) -> some View {
        onFrameChange(in: coordinateSpace) { frame in
            binding.wrappedValue = frame
        }
    }
}
