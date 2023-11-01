//
//  CustomColorPicker.swift
//  Ice
//

import Combine
import SwiftUI

struct CustomColorPicker: NSViewRepresentable {
    class Coordinator {
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
                        self?.selection = color.cgColor
                    }
                }
                .store(in: &c)

            NSColorPanel.shared
                .publisher(for: \.isVisible)
                .sink { [weak self, weak nsView] isVisible in
                    guard
                        let self,
                        isVisible,
                        nsView?.isActive == true
                    else {
                        return
                    }
                    NSColorPanel.shared.showsAlpha = supportsOpacity
                    NSColorPanel.shared.mode = mode
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
        if #available(macOS 14.0, *) {
            nsView.supportsAlpha = supportsOpacity
        }
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
