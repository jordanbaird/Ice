//
//  CustomColorPicker.swift
//  Ice
//

import Combine
import SwiftUI

struct CustomColorPicker: View {
    @Binding var selection: CGColor?
    @StateObject private var model = CustomColorPickerModel()
    @State private var isActive = false

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

    init(
        selection: Binding<CGColor?>,
        supportsOpacity: Bool,
        mode: NSColorPanel.Mode
    ) {
        self._selection = selection
        self.supportsOpacity = supportsOpacity
        self.mode = mode
    }

    init(
        selection: Binding<CGColor>,
        supportsOpacity: Bool,
        mode: NSColorPanel.Mode
    ) {
        self._selection = Binding(selection)
        self.supportsOpacity = supportsOpacity
        self.mode = mode
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
            .onDisappear {
                deactivate()
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

        var c = Set<AnyCancellable>()

        NSColorPanel.shared.publisher(for: \.color)
            .dropFirst()
            .sink { color in
                if selection != color.cgColor {
                    selection = color.cgColor
                }
            }
            .store(in: &c)

        NSColorPanel.shared.publisher(for: \.isVisible)
            .sink { isVisible in
                if !isVisible {
                    deactivate()
                }
            }
            .store(in: &c)

        model.cancellables = c

        isActive = true
    }

    private func deactivate() {
        for cancellable in model.cancellables {
            cancellable.cancel()
        }
        model.cancellables.removeAll()
        isActive = false
    }
}
