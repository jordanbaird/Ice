//
//  CustomColorPicker.swift
//  Ice
//

import Combine
import SwiftUI

struct CustomColorPicker: NSViewRepresentable {
    final class Coordinator {
        @Binding var selection: CGColor

        let supportsOpacity: Bool
        let mode: NSColorPanel.Mode

        private var cancellables = Set<AnyCancellable>()

        init(
            selection: Binding<CGColor>,
            supportsOpacity: Bool,
            mode: NSColorPanel.Mode
        ) {
            self._selection = selection
            self.supportsOpacity = supportsOpacity
            self.mode = mode
        }

        func configure(with nsView: NSColorWell) {
            var c = Set<AnyCancellable>()

            nsView
                .publisher(for: \.color)
                .removeDuplicates()
                .sink { [weak self] color in
                    DispatchQueue.main.async {
                        if self?.selection != color.cgColor {
                            self?.selection = color.cgColor
                        }
                    }
                }
                .store(in: &c)

            NSColorPanel.shared
                .publisher(for: \.isVisible)
                .sink { [weak self, weak nsView] isVisible in
                    guard
                        let self,
                        let nsView,
                        isVisible,
                        nsView.isActive
                    else {
                        return
                    }
                    NSColorPanel.shared.showsAlpha = supportsOpacity
                    NSColorPanel.shared.mode = mode
                    if let window = nsView.window {
                        NSColorPanel.shared.level = window.level + 1
                    }
                    if NSColorPanel.shared.frame.origin == .zero {
                        NSColorPanel.shared.center()
                    }
                }
                .store(in: &c)

            NSColorPanel.shared
                .publisher(for: \.level)
                .sink { [weak nsView] level in
                    guard
                        let nsView,
                        nsView.isActive,
                        let window = nsView.window,
                        level != window.level + 1
                    else {
                        return
                    }
                    NSColorPanel.shared.level = window.level + 1
                }
                .store(in: &c)

            cancellables = c
        }
    }

    @Binding var selection: CGColor

    let supportsOpacity: Bool
    let mode: NSColorPanel.Mode

    func makeNSView(context: Context) -> NSColorWell {
        let nsView = NSColorWell()
        context.coordinator.configure(with: nsView)
        return nsView
    }

    func updateNSView(_ nsView: NSColorWell, context: Context) {
        if let color = NSColor(cgColor: selection) {
            nsView.color = color
        }
        nsView.supportsAlpha = supportsOpacity
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            selection: $selection,
            supportsOpacity: supportsOpacity,
            mode: mode
        )
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView: NSColorWell,
        context: Context
    ) -> CGSize? {
        switch nsView.controlSize {
        case .large:
            CGSize(width: 55, height: 30)
        case .regular:
            CGSize(width: 44, height: 24)
        case .small:
            CGSize(width: 33, height: 18)
        case .mini:
            CGSize(width: 29, height: 16)
        @unknown default:
            nsView.intrinsicContentSize
        }
    }
}
