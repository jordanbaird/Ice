//
//  CustomColorPicker.swift
//  Ice
//

import Combine
import SwiftUI

struct CustomColorPicker: View {
    @Binding var selection: CGColor?
    @State private var isActive = false
    @State private var cancellables = Set<AnyCancellable>()

    let supportsOpacity: Bool
    let mode: NSColorPanel.Mode

    private var fill: AnyShapeStyle {
        if let selection {
            AnyShapeStyle(
                Color(cgColor: selection)
            )
        } else {
            AnyShapeStyle(
                Color.white
                    .gradient
                    .opacity(0.1)
                    .blendMode(.softLight)
            )
        }
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 5)
            .fill(fill)
            .shadow(radius: 1)
            .overlay {
                RoundedRectangle(cornerRadius: 5)
                    .stroke(isActive ? .primary : .secondary)
                    .blendMode(selection == nil ? .normal : .overlay)
            }
            .frame(width: 40, height: 24)
            .contentShape(Rectangle())
            .help("Select a color")
            .onTapGesture {
                activate()
            }
    }

    private func activate() {
        deactivate()

        NSColorPanel.shared.showsAlpha = supportsOpacity
        if
            let selection,
            let color = NSColor(cgColor: selection)
        {
            NSColorPanel.shared.color = color
        }
        NSColorPanel.shared.mode = mode
        NSColorPanel.shared.makeKeyAndOrderFront(self)

        NSColorPanel.shared.publisher(for: \.color)
            .dropFirst()
            .sink { color in
                if selection != color.cgColor {
                    selection = color.cgColor
                }
            }
            .store(in: &cancellables)

        NSColorPanel.shared.publisher(for: \.isVisible)
            .sink { isVisible in
                if !isVisible {
                    deactivate()
                }
            }
            .store(in: &cancellables)

        isActive = true
    }

    private func deactivate() {
        for cancellable in cancellables {
            cancellable.cancel()
        }
        cancellables.removeAll()
        isActive = false
    }
}
