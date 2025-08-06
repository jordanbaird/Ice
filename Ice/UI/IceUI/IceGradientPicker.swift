//
//  IceGradientPicker.swift
//  Ice
//

import Combine
import SwiftUI

struct IceGradientPicker<Label: View>: View {
    @Binding private var gradient: IceGradient
    @State private var selection: Int?
    @State private var cancellable: AnyCancellable?

    private let supportsOpacity: Bool
    private let label: Label

    init(
        gradient: Binding<IceGradient>,
        supportsOpacity: Bool = true,
        @ViewBuilder label: () -> Label
    ) {
        self._gradient = gradient
        self.supportsOpacity = supportsOpacity
        self.label = label()
    }

    init(
        _ labelKey: LocalizedStringKey,
        gradient: Binding<IceGradient>,
        supportsOpacity: Bool = true
    ) where Label == Text {
        self._gradient = gradient
        self.supportsOpacity = supportsOpacity
        self.label = Text(labelKey)
    }

    /// Creates a new gradient picker.
    ///
    /// - Parameters:
    ///   - gradient: A binding to a gradient.
    ///   - supportsOpacity: A Boolean value indicating whether the
    ///     picker should support opacity.
    init(
        gradient: Binding<IceGradient>,
        supportsOpacity: Bool = true
    ) where Label == EmptyView {
        self._gradient = gradient
        self.supportsOpacity = supportsOpacity
        self.label = EmptyView()
    }

    var body: some View {
        LabeledContent {
            IceGradientPickerRoot(
                gradient: $gradient,
                selection: $selection,
                supportsOpacity: supportsOpacity
            )
            .onWindowChange { window in
                cancellable = window?.publisher(for: \.isVisible)
                    .removeDuplicates()
                    .receive(on: DispatchQueue.main)
                    .sink { isVisible in
                        if !isVisible {
                            selection = nil
                        }
                    }
            }
        } label: {
            label
        }
    }
}

private struct IceGradientPickerRoot: View {
    @Environment(\.isEnabled) private var isEnabled

    @Binding var gradient: IceGradient
    @Binding var selection: Int?
    @State private var lastUpdated: Int?
    @State private var cancellables = Set<AnyCancellable>()

    let supportsOpacity: Bool

    private let handleWidth: CGFloat = 10

    private var borderShape: some InsettableShape {
        if #available(macOS 26.0, *) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
        } else {
            RoundedRectangle(cornerRadius: 5, style: .circular)
        }
    }

    var body: some View {
        gradient.swiftUIView(using: .displayP3)
            .clipShape(borderShape)
            .overlay {
                borderView
            }
            .padding(.vertical, 2)
            .overlay {
                GeometryReader { geometry in
                    insertionReader(geometry: geometry)
                    handles(geometry: geometry)
                }
                .padding(.horizontal, handleWidth / 2)
            }
            .frame(width: 200, height: 24)
            .shadow(radius: 2)
            .onTapGesture(count: 2) {
                distributeStops()
            }
            .onKeyDown(key: .delete, isEnabled: selection != nil) {
                deleteSelectedStop()
                return .handled
            }
            .onKeyDown(key: .escape, isEnabled: selection != nil) {
                selection = nil
                dismissColorPanel()
                return .handled
            }
            .onChange(of: gradient) { oldValue, newValue in
                gradientChanged(from: oldValue, to: newValue)
            }
            .onChange(of: selection) { oldValue, newValue in
                selectionChanged(from: oldValue, to: newValue)
            }
            .compositingGroup()
            .allowsHitTesting(isEnabled)
            .opacity(isEnabled ? 1 : 0.5)
    }

    @ViewBuilder
    private var borderView: some View {
        borderShape
            .strokeBorder(.tertiary)
            .overlay {
                centerTickMark
            }
    }

    @ViewBuilder
    private var centerTickMark: some View {
        Rectangle()
            .fill(.tertiary)
            .frame(width: 1, height: 6)
    }

    @ViewBuilder
    private func insertionReader(geometry: GeometryProxy) -> some View {
        Color.clear
            .contentShape(borderShape)
            .onTapGesture { location in
                insertStop(at: (location.x / geometry.size.width), select: true)
            }
    }

    @ViewBuilder
    private func handles(geometry: GeometryProxy) -> some View {
        ForEach(gradient.stops.indices, id: \.self) { index in
            IceGradientPickerHandle(
                gradient: $gradient,
                selection: $selection,
                lastUpdated: $lastUpdated,
                index: index,
                geometry: geometry,
                width: handleWidth
            )
        }
    }

    private func insertStop(at location: CGFloat, select: Bool) {
        var location = location.clamped(to: 0...1)
        if abs(location - 0.5) <= 0.025 {
            location = 0.5
        }
        if let color = gradient.color(at: location) {
            gradient.stops.append(.stop(color, location: location))
        } else {
            gradient.stops.append(.black(location: location))
        }
        if select, let index = gradient.stops.indices.last {
            DispatchQueue.main.async {
                self.selection = index
            }
        }
    }

    private func gradientChanged(from oldValue: IceGradient, to newValue: IceGradient) {
        guard oldValue != newValue else {
            return
        }
        if newValue.stops.isEmpty {
            gradient = oldValue
        }
    }

    private func selectionChanged(from oldValue: Int?, to newValue: Int?) {
        guard oldValue != newValue else {
            return
        }

        stopColorPanelObservers()

        if newValue != nil {
            dismissColorPanel()
            openColorPanel()
            startColorPanelObservers()
        }
    }

    private func startColorPanelObservers() {
        if
            let selection,
            gradient.stops.indices.contains(selection),
            let color = NSColor(cgColor: gradient.stops[selection].color),
            NSColorPanel.shared.color != color
        {
            NSColorPanel.shared.color = color
        }

        var c = Set<AnyCancellable>()

        NSColorPanel.shared.publisher(for: \.color)
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { color in
                guard
                    let selection,
                    NSColorPanel.shared.isVisible,
                    gradient.stops.indices.contains(selection),
                    gradient.stops[selection].color != color.cgColor
                else {
                    return
                }
                gradient.stops[selection].color = color.cgColor
            }
            .store(in: &c)

        NSColorPanel.shared.publisher(for: \.isVisible)
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { isVisible in
                guard selection != nil else {
                    return
                }
                guard isVisible else {
                    selection = nil
                    return
                }
                if NSColorPanel.shared.showsAlpha != supportsOpacity {
                    NSColorPanel.shared.showsAlpha = supportsOpacity
                }
            }
            .store(in: &c)

        cancellables = c
    }

    private func stopColorPanelObservers() {
        for cancellable in cancellables {
            cancellable.cancel()
        }
        cancellables.removeAll()
    }

    private func openColorPanel() {
        if !NSColorPanel.shared.isVisible {
            NSColorPanel.shared.orderFrontRegardless()
        }
    }

    private func dismissColorPanel() {
        if NSColorPanel.shared.isVisible {
            NSColorPanel.shared.close()
        }
    }

    private func deleteSelectedStop() {
        guard
            let index = selection.take(),
            gradient.stops.indices.contains(index)
        else {
            return
        }
        gradient.stops.remove(at: index)
    }

    private func distributeStops() {
        guard !gradient.stops.isEmpty else {
            return
        }
        if gradient.stops.count == 1 {
            gradient.stops[0].location = 0.5
        } else {
            let last = CGFloat(gradient.stops.count - 1)
            let newStops = gradient.stops.lazy
                .sorted { $0.location < $1.location }
                .enumerated()
                .map { n, stop in
                    stop.withLocation(CGFloat(n) / last)
                }
            gradient.stops = newStops
        }
    }
}

private struct IceGradientPickerHandle: View {
    @Binding var gradient: IceGradient
    @Binding var selection: Int?
    @Binding var lastUpdated: Int?

    let index: Int
    let geometry: GeometryProxy
    let width: CGFloat

    private var isSelected: Bool {
        index == selection
    }

    private var isLastUpdated: Bool {
        index == lastUpdated
    }

    private var stop: IceGradient.ColorStop? {
        guard gradient.stops.indices.contains(index) else {
            return nil
        }
        return gradient.stops[index]
    }

    private var borderShape: some InsettableShape {
        if #available(macOS 26.0, *) {
            Capsule(style: .continuous)
        } else {
            Capsule(style: .circular)
        }
    }

    var body: some View {
        handleView
            .gesture(
                DragGesture(minimumDistance: 2).onChanged { value in
                    update(with: value)
                }
            )
            .onTapGesture {
                selection = isSelected ? nil : index
            }
            .onKeyPress(.space) {
                selection = isSelected ? nil : index
                return .handled
            }
            .onChange(of: isSelected) { _, newValue in
                if newValue {
                    lastUpdated = index
                }
            }
    }

    @ViewBuilder
    private var handleView: some View {
        if let stop {
            borderShape
                .fill(Color(cgColor: stop.color))
                .strokeBorder(isSelected ? AnyShapeStyle(.clear) : AnyShapeStyle(.tertiary))
                .background(
                    isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear),
                    in: borderShape.inset(by: -2)
                )
                .contentShape([.interaction, .focusEffect], borderShape)
                .frame(width: width)
                .position(x: geometry.size.width * stop.location, y: geometry.size.height / 2)
                .zIndex(isLastUpdated ? 2 : stop.location)
                .compositingGroup()
        }
    }

    private func update(with value: DragGesture.Value) {
        guard gradient.stops.indices.contains(index) else {
            return
        }

        var location = (value.location.x / geometry.size.width).clamped(to: 0...1)

        if
            !NSEvent.modifierFlags.contains(.command),
            abs(value.velocity.width) <= 75 && abs(location - 0.5) <= 0.025
        {
            location = 0.5
        }

        gradient.stops[index].location = location
        lastUpdated = index
    }
}
