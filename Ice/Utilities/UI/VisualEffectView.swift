//
//  VisualEffectView.swift
//  Ice
//

import SwiftUI

/// A SwiftUI view that wraps a Cocoa `NSVisualEffectView`.
struct VisualEffectView: NSViewRepresentable {
    private let material: NSVisualEffectView.Material
    private let blendingMode: NSVisualEffectView.BlendingMode
    private let state: NSVisualEffectView.State
    private let isEmphasized: Bool

    /// Creates a visual effect view with the given material, blending
    /// mode, and state, setting whether the view is displayed with an
    /// emphasized appearance based on the value of a Boolean flag.
    ///
    /// - Parameters:
    ///   - material: The material of the view.
    ///   - blendingMode: The blending mode of the view.
    ///   - state: A value that determines when the view should appear
    ///     active.
    ///   - isEmphasized: A Boolean value that indicates whether the
    ///     view should be displayed with an emphasized appearance.
    init(
        material: NSVisualEffectView.Material,
        blendingMode: NSVisualEffectView.BlendingMode = .behindWindow,
        state: NSVisualEffectView.State = .followsWindowActiveState,
        isEmphasized: Bool = false
    ) {
        self.material = material
        self.blendingMode = blendingMode
        self.state = state
        self.isEmphasized = isEmphasized
    }

    func makeNSView(context: Context) -> NSView {
        let nsView = NSVisualEffectView()
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = state
        nsView.isEmphasized = isEmphasized
        return nsView
    }

    func updateNSView(_: NSView, context: Context) { }
}
