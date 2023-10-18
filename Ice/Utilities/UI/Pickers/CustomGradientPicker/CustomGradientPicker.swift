//
//  CustomGradientPicker.swift
//  Ice
//

import Combine
import SwiftUI

struct CustomGradientPicker: View {
    @Binding var gradient: CustomGradient
    @StateObject private var model: CustomGradientPickerModel
    @State private var window: NSWindow?

    let supportsOpacity: Bool
    let mode: NSColorPanel.Mode

    /// Creates a new gradient picker.
    ///
    /// - Parameters:
    ///   - gradient: A binding to a gradient.
    ///   - supportsOpacity: A Boolean value indicating whether the
    ///     picker should support opacity.
    ///   - mode: The mode that the color panel should take on when
    ///     picking a color for the gradient.
    init(
        gradient: Binding<CustomGradient>,
        supportsOpacity: Bool,
        mode: NSColorPanel.Mode
    ) {
        let model = CustomGradientPickerModel(zOrderedStops: gradient.wrappedValue.stops)
        self._model = StateObject(wrappedValue: model)
        self._gradient = gradient
        self.supportsOpacity = supportsOpacity
        self.mode = mode
    }

    var body: some View {
        gradientView
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay {
                RoundedRectangle(cornerRadius: 5)
                    .stroke()
                    .overlay {
                        Rectangle()
                            .frame(width: 1, height: 6)
                    }
                    .foregroundStyle(.secondary.opacity(0.75))
                    .blendMode(.softLight)
            }
            .shadow(radius: 1)
            .frame(width: 200, height: 18)
            .overlay {
                GeometryReader { geometry in
                    selectionReader(geometry: geometry)
                    insertionReader(geometry: geometry)
                    handles(geometry: geometry)
                }
            }
            .foregroundStyle(Color(white: 0.9))
            .onKeyDown(key: .escape) {
                model.selectedStop = nil
            }
            .onKeyDown(key: .delete) {
                guard
                    let selectedStop = model.selectedStop,
                    let index = gradient.stops.firstIndex(of: selectedStop)
                else {
                    return
                }
                gradient.stops.remove(at: index)
                model.selectedStop = nil
            }
            .readWindow(window: $window)
    }

    @ViewBuilder
    private var gradientView: some View {
        if gradient.stops.isEmpty {
            Rectangle()
                .fill(.white.gradient.opacity(0.1))
                .blendMode(.softLight)
        } else {
            gradient
        }
    }

    @ViewBuilder
    private func selectionReader(geometry: GeometryProxy) -> some View {
        Color.clear
            .localEventMonitor(mask: .leftMouseDown) { event in
                guard
                    let window = event.window,
                    self.window === window
                else {
                    return event
                }
                let locationInWindow = event.locationInWindow
                guard window.contentLayoutRect.contains(locationInWindow) else {
                    return event
                }
                let globalFrame = geometry.frame(in: .global)
                let flippedLocation = CGPoint(
                    x: locationInWindow.x,
                    y: window.frame.height - locationInWindow.y
                )
                if !globalFrame.contains(flippedLocation) {
                    model.selectedStop = nil
                }
                return event
            }
    }

    @ViewBuilder
    private func insertionReader(geometry: GeometryProxy) -> some View {
        Color.clear
            .contentShape(RoundedRectangle(cornerRadius: 5))
            .gesture(
                DragGesture(
                    minimumDistance: 0,
                    coordinateSpace: .local
                )
                .onEnded { value in
                    guard abs(value.translation.width) <= 2 else {
                        return
                    }
                    let frame = geometry.frame(in: .local)
                    guard frame.contains(value.location) else {
                        return
                    }
                    let x = value.location.x
                    let width = frame.width - 10
                    let location = (x / width) - (6 / width)
                    insertStop(at: location)
                }
            )
    }

    @ViewBuilder
    private func handles(geometry: GeometryProxy) -> some View {
        ForEach(gradient.stops.indices, id: \.self) { index in
            CustomGradientPickerHandle(
                gradient: $gradient,
                model: model,
                index: index,
                supportsOpacity: supportsOpacity,
                mode: mode,
                geometry: geometry
            )
        }
    }

    /// Inserts a new stop with the appropriate color
    /// at the given location in the gradient.
    private func insertStop(at location: CGFloat) {
        var location = location.clamped(to: 0...1)
        if (0.48...0.52).contains(location) {
            location = 0.5
        }
        let newStop: ColorStop
        if
            !gradient.stops.isEmpty,
            let color = gradient.color(at: location)
        {
            newStop = ColorStop(
                color: color,
                location: location
            )
        } else {
            newStop = ColorStop(
                color: CGColor(
                    red: 0,
                    green: 0,
                    blue: 0,
                    alpha: 1
                ),
                location: location
            )
        }
        gradient.stops.append(newStop)
        DispatchQueue.main.async {
            model.selectedStop = newStop
        }
    }
}

private struct CustomGradientPickerHandle: View {
    @Binding var gradient: CustomGradient
    @ObservedObject var model: CustomGradientPickerModel

    let index: Int
    let supportsOpacity: Bool
    let mode: NSColorPanel.Mode
    let geometry: GeometryProxy
    let width: CGFloat = 8
    let height: CGFloat = 22

    private var stop: ColorStop? {
        get {
            guard gradient.stops.indices.contains(index) else {
                return nil
            }
            return gradient.stops[index]
        }
        nonmutating set {
            guard gradient.stops.indices.contains(index) else {
                return
            }
            if let newValue {
                gradient.stops[index] = newValue
            } else {
                gradient.stops.remove(at: index)
            }
        }
    }

    private var stroke: AnyShapeStyle {
        if model.selectedStop == stop {
            AnyShapeStyle(.primary)
        } else {
            AnyShapeStyle(.secondary.opacity(0.75))
        }
    }

    var body: some View {
        if let stop {
            gradientPickerHandle(with: stop)
        }
    }

    @ViewBuilder
    private func gradientPickerHandle(with stop: ColorStop) -> some View {
        Capsule()
            .inset(by: -1)
            .fill(Color(cgColor: stop.color))
            .overlay {
                Capsule()
                    .inset(by: -1)
                    .stroke()
                    .foregroundStyle(stroke)
                    .blendMode(.softLight)
            }
            .frame(width: width, height: height)
            .offset(
                x: (geometry.size.width - width) * stop.location,
                y: (geometry.size.height - height) / 2
            )
            .shadow(radius: 1)
            .gesture(
                DragGesture(minimumDistance: 5)
                    .onChanged { value in
                        update(
                            with: value.location.x,
                            shouldSnap: abs(value.velocity.width) <= 75
                        )
                    }
                    .onEnded { value in
                        update(
                            with: value.location.x,
                            shouldSnap: true
                        )
                    }
            )
            .onTapGesture(count: 2) {
                if gradient.stops.count == 1 {
                    gradient.stops[0].location = 0.5
                } else {
                    let last = CGFloat(gradient.stops.count - 1)
                    gradient.stops = gradient.sortedStops
                        .enumerated()
                        .map { n, stop in
                            var stop = stop
                            stop.location = CGFloat(n) / last
                            return stop
                        }
                }
            }
            .onTapGesture {
                model.selectedStop = stop
            }
            .zIndex(Double(model.zOrderedStops.firstIndex(of: stop) ?? 0))
            .onReceive(model.$selectedStop) { _ in
                deactivate()
                DispatchQueue.main.async {
                    if model.selectedStop == self.stop {
                        activate()
                    }
                }
            }
    }

    private func update(with location: CGFloat, shouldSnap: Bool) {
        guard var stop else {
            return
        }
        let newLocation = (
            location - (width / 2)
        ) / (
            geometry.size.width - width
        )
        if let index = model.zOrderedStops.firstIndex(of: stop) {
            model.zOrderedStops.remove(at: index)
        }
        let isSelected = model.selectedStop == stop
        if
            shouldSnap,
            (0.48...0.52).contains(newLocation)
        {
            stop.location = 0.5
        } else {
            stop.location = min(1, max(0, newLocation))
        }
        self.stop = stop
        if isSelected {
            model.selectedStop = stop
        }
        model.zOrderedStops.append(stop)
    }

    private func activate() {
        deactivate()

        NSColorPanel.shared.showsAlpha = supportsOpacity
        NSColorPanel.shared.mode = mode
        if let color = stop.flatMap({ NSColor(cgColor: $0.color) }) {
            NSColorPanel.shared.color = color
        }
        NSColorPanel.shared.orderFrontRegardless()

        var c = Set<AnyCancellable>()

        NSColorPanel.shared.publisher(for: \.color)
            .dropFirst()
            .sink { color in
                if stop?.color != color.cgColor {
                    stop?.color = color.cgColor
                    model.selectedStop = stop
                }
            }
            .store(in: &c)

        NSColorPanel.shared.publisher(for: \.isVisible)
            .sink { isVisible in
                if !isVisible {
                    model.selectedStop = nil
                }
            }
            .store(in: &c)

        model.cancellables = c
    }

    private func deactivate() {
        for cancellable in model.cancellables {
            cancellable.cancel()
        }
        model.cancellables.removeAll()
    }
}

#if DEBUG
private struct CustomGradientPickerPreview: View {
    @State private var gradient = CustomGradient(unsortedStops: [
        ColorStop(color: NSColor.systemRed.cgColor, location: 0),
        ColorStop(color: NSColor.systemBlue.cgColor, location: 1 / 3),
        ColorStop(color: NSColor.systemIndigo.cgColor, location: 2 / 3),
        ColorStop(color: NSColor.systemPurple.cgColor, location: 1),
    ])

    var body: some View {
        CustomGradientPicker(
            gradient: $gradient,
            supportsOpacity: false,
            mode: .crayon
        )
    }
}

#Preview {
    CustomGradientPickerPreview()
        .padding()
}
#endif
