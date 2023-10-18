//
//  GradientPicker.swift
//  Ice
//

import Combine
import SwiftUI

struct GradientPicker: View {
    @Binding var gradient: CustomGradient
    @StateObject private var model = GradientPickerModel()
    @State private var zOrderedStops: [ColorStop]
    @State private var window: NSWindow?

    let supportsOpacity: Bool
    let mode: NSColorPanel.Mode

    /// Creates a new gradient picker.
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
        self._gradient = gradient
        self.zOrderedStops = gradient.wrappedValue.stops
        self.supportsOpacity = supportsOpacity
        self.mode = mode
    }

    var body: some View {
        gradientView
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay {
                RoundedRectangle(cornerRadius: 5)
                    .stroke()
                    .foregroundStyle(.secondary.opacity(0.75))
                    .blendMode(.softLight)
            }
            .shadow(radius: 1)
            .frame(width: 200, height: 18)
            .overlay {
                GeometryReader { geometry in
                    Color.clear
                        .contentShape(RoundedRectangle(cornerRadius: 5))
                        .simultaneousGesture(
                            DragGesture(
                                minimumDistance: 0,
                                coordinateSpace: .local
                            )
                            .onEnded { value in
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
                        .localEventMonitor(mask: .leftMouseDown) { event in
                            guard
                                let window = event.window,
                                self.window === window
                            else {
                                return event
                            }
                            let globalFrame = geometry.frame(in: .global)
                            let locationInWindow = event.locationInWindow
                            let flippedLocation = CGPoint(
                                x: locationInWindow.x,
                                y: window.frame.height - locationInWindow.y
                            )
                            if
                                window.contentLayoutRect.contains(locationInWindow),
                                !globalFrame.contains(flippedLocation)
                            {
                                model.selectedStop = nil
                            }
                            return event
                        }

                    ForEach(gradient.stops.indices, id: \.self) { index in
                        GradientPickerHandle(
                            gradient: $gradient,
                            stop: $gradient.stops[index],
                            zOrderedStops: $zOrderedStops,
                            model: model,
                            supportsOpacity: supportsOpacity,
                            mode: mode,
                            geometry: geometry
                        )
                    }
                }
            }
            .foregroundStyle(Color(white: 0.9))
            .onKeyDown(key: .escape) {
                model.selectedStop = nil
            }
            .onKeyDown(key: .delete) {
                guard let selectedStop = model.selectedStop else {
                    return
                }
                if let index = gradient.stops.firstIndex(of: selectedStop) {
                    gradient.stops.remove(at: index)
                }
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

    /// Inserts a new stop with the appropriate color
    /// at the given location in the gradient.
    private func insertStop(at location: CGFloat) {
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
        model.selectedStop = newStop
    }
}

private struct GradientPickerHandle: View {
    @Binding var gradient: CustomGradient
    @Binding var stop: ColorStop
    @Binding var zOrderedStops: [ColorStop]
    @ObservedObject var model: GradientPickerModel

    let supportsOpacity: Bool
    let mode: NSColorPanel.Mode
    let geometry: GeometryProxy
    let width: CGFloat = 8
    let height: CGFloat = 22

    var stroke: AnyShapeStyle {
        if model.selectedStop == stop {
            AnyShapeStyle(.primary)
        } else {
            AnyShapeStyle(.secondary.opacity(0.75))
        }
    }

    var body: some View {
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
            .simultaneousGesture(
                DragGesture(minimumDistance: 5)
                    .onChanged { value in
                        update(
                            with: value.location.x,
                            snap: abs(value.velocity.width) <= 75
                        )
                    }
                    .onEnded { value in
                        update(
                            with: value.location.x,
                            snap: true
                        )
                    }
            )
            .simultaneousGesture(
                TapGesture(count: 2)
                    .onEnded {
                        if let index = gradient.stops.firstIndex(of: stop) {
                            gradient.stops.remove(at: index)
                        }
                    }
            )
            .onTapGesture {
                model.selectedStop = stop
            }
            .zIndex(Double(zOrderedStops.firstIndex(of: stop) ?? 0))
            .onReceive(model.$selectedStop) { _ in
                deactivate()
                DispatchQueue.main.async {
                    if model.selectedStop == stop {
                        activate()
                    }
                }
            }
    }

    private func update(with location: CGFloat, snap: Bool) {
        let newLocation = (
            location - (width / 2)
        ) / (
            geometry.size.width - width
        )
        if let index = zOrderedStops.firstIndex(of: stop) {
            zOrderedStops.remove(at: index)
        }
        let isSelected = model.selectedStop == stop
        if snap {
            if (0.23...0.27).contains(newLocation) {
                stop.location = 0.25
            } else if (0.48...0.52).contains(newLocation) {
                stop.location = 0.5
            } else if (0.73...0.77).contains(newLocation) {
                stop.location = 0.75
            } else {
                stop.location = min(1, max(0, newLocation))
            }
        } else {
            stop.location = min(1, max(0, newLocation))
        }
        if isSelected {
            model.selectedStop = stop
        }
        zOrderedStops.append(stop)
    }

    private func activate() {
        deactivate()

        NSColorPanel.shared.showsAlpha = supportsOpacity
        NSColorPanel.shared.mode = mode
        if let color = NSColor(cgColor: stop.color) {
            NSColorPanel.shared.color = color
        }
        NSColorPanel.shared.orderFrontRegardless()

        var c = Set<AnyCancellable>()

        NSColorPanel.shared.publisher(for: \.color)
            .dropFirst()
            .sink { color in
                if stop.color != color.cgColor {
                    stop.color = color.cgColor
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
struct GradientPickerPreview: View {
    @State private var gradient = CustomGradient(unsortedStops: [
        ColorStop(color: NSColor.systemRed.cgColor, location: 0),
        ColorStop(color: NSColor.systemBlue.cgColor, location: 1 / 3),
        ColorStop(color: NSColor.systemIndigo.cgColor, location: 2 / 3),
        ColorStop(color: NSColor.systemPurple.cgColor, location: 1),
    ])

    var body: some View {
        GradientPicker(
            gradient: $gradient,
            supportsOpacity: false,
            mode: .crayon
        )
    }
}
#Preview {
    GradientPickerPreview()
        .padding()
}
#endif
