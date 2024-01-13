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
    /// Adds an action to perform when the view's frame changes.
    ///
    /// - Parameters:
    ///   - coordinateSpace: The coordinate space to use as a reference
    ///     when accessing the view's frame.
    ///   - action: The action to perform when the view's frame changes.
    ///     The `action` closure passes the new frame as its parameter.
    ///
    /// - Returns: A view that triggers `action` when its frame changes.
    func onFrameChange(
        in coordinateSpace: CoordinateSpace = .local,
        perform action: @escaping (CGRect) -> Void
    ) -> some View {
        background {
            GeometryReader { proxy in
                Color.clear
                    .preference(
                        key: FramePreferenceKey.self,
                        value: proxy.frame(in: coordinateSpace)
                    )
                    .onPreferenceChange(FramePreferenceKey.self, perform: action)
            }
        }
    }

    /// Returns a version of this view that updates the given binding
    /// when its frame changes.
    ///
    /// - Parameters:
    ///   - coordinateSpace: The coordinate space to use as a reference
    ///     when accessing the view's frame.
    ///   - binding: A binding to update when the view's frame changes.
    ///
    /// - Returns: A view that updates `binding` when its frame changes.
    func onFrameChange(
        in coordinateSpace: CoordinateSpace = .local,
        update binding: Binding<CGRect>
    ) -> some View {
        onFrameChange(in: coordinateSpace) { frame in
            binding.wrappedValue = frame
        }
    }
}
