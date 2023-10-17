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

    private var stroke: AnyShapeStyle {
        if isActive {
            AnyShapeStyle(.primary)
        } else {
            AnyShapeStyle(.secondary.opacity(0.75))
        }
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 5)
            .fill(fill)
            .overlay {
                RoundedRectangle(cornerRadius: 5)
                    .stroke()
                    .foregroundStyle(stroke)
                    .blendMode(.softLight)
            }
            .frame(width: 40, height: 24)
            .shadow(radius: 1)
            .contentShape(Rectangle())
            .foregroundStyle(Color(white: 0.9))
            .help("Select a color")
            .onTapGesture {
                activate()
            }
    }

    private func activate() {
        deactivate()

        NSColorPanel.shared.showsAlpha = supportsOpacity
        NSColorPanel.shared.mode = mode
        if
            let selection,
            let color = NSColor(cgColor: selection)
        {
            NSColorPanel.shared.color = color
        }
        NSColorPanel.shared.orderFrontRegardless()

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
