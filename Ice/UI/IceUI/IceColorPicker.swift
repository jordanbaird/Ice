//
//  IceColorPicker.swift
//  Ice
//

import Combine
import SwiftUI

struct IceColorPicker<Label: View>: View {
    @Binding private var selection: CGColor
    @State private var isActive: Bool = false

    private let supportsOpacity: Bool
    private let label: Label

    init(
        selection: Binding<CGColor>,
        supportsOpacity: Bool = true,
        @ViewBuilder label: () -> Label
    ) {
        self._selection = selection
        self.supportsOpacity = supportsOpacity
        self.label = label()
    }

    init(
        _ labelKey: LocalizedStringKey,
        selection: Binding<CGColor>,
        supportsOpacity: Bool = true
    ) where Label == Text {
        self._selection = selection
        self.supportsOpacity = supportsOpacity
        self.label = Text(labelKey)
    }

    /// Creates a new color picker.
    ///
    /// - Parameters:
    ///   - gradient: A binding to a color.
    ///   - supportsOpacity: A Boolean value indicating whether the
    ///     picker should support opacity.
    init(
        selection: Binding<CGColor>,
        supportsOpacity: Bool = true
    ) where Label == EmptyView {
        self._selection = selection
        self.supportsOpacity = supportsOpacity
        self.label = EmptyView()
    }

    var body: some View {
        IceLabeledContent {
            IceColorPickerRoot(
                selection: $selection,
                isActive: $isActive,
                supportsOpacity: supportsOpacity
            )
            .onKeyDown(key: .escape, isEnabled: isActive) {
                isActive = false
                NSColorPanel.shared.close()
                return .handled
            }
        } label: {
            label
        }
    }
}

private struct IceColorPickerRoot: NSViewRepresentable {
    @Binding var selection: CGColor
    @Binding var isActive: Bool

    let supportsOpacity: Bool

    func makeNSView(context: Context) -> NSColorWell {
        let colorWell = NSColorWell()
        updateNSView(colorWell, context: context)
        context.coordinator.configure(with: colorWell)
        return colorWell
    }

    func updateNSView(_ colorWell: NSColorWell, context: Context) {
        if colorWell.supportsAlpha != supportsOpacity {
            colorWell.supportsAlpha = supportsOpacity
        }

        if
            let color = NSColor(cgColor: selection),
            colorWell.color != color
        {
            colorWell.color = color
        }

        if isActive != colorWell.isActive {
            if isActive, let window = colorWell.window, window.isVisible {
                colorWell.activate(true)
            } else {
                colorWell.deactivate()
            }
        }
    }

    func makeCoordinator() -> IceColorPickerCoordinator {
        IceColorPickerCoordinator(selection: $selection, isActive: $isActive)
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView colorWell: NSColorWell,
        context: Context
    ) -> CGSize? {
        colorWell.intrinsicContentSize
    }
}

@MainActor
private final class IceColorPickerCoordinator {
    @Binding var selection: CGColor
    @Binding var isActive: Bool

    private var cancellables = Set<AnyCancellable>()

    init(selection: Binding<CGColor>, isActive: Binding<Bool>) {
        self._selection = selection
        self._isActive = isActive
    }

    func configure(with colorWell: NSColorWell) {
        var c = Set<AnyCancellable>()

        colorWell.publisher(for: \.color).removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] color in
                guard let self else {
                    return
                }
                let selection = color.cgColor
                if self.selection != selection {
                    self.selection = selection
                }
            }
            .store(in: &c)

        colorWell.publisher(for: \.isActive).removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isActive in
                guard let self else {
                    return
                }
                if self.isActive != isActive {
                    self.isActive = isActive
                }
            }
            .store(in: &c)

        colorWell.publisher(for: \.window).publisher(for: \.isVisible)
            .replaceNil(with: false).removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isVisible in
                guard let self else {
                    return
                }
                if !isVisible, isActive {
                    isActive = false
                }
            }
            .store(in: &c)

        cancellables = c
    }
}
