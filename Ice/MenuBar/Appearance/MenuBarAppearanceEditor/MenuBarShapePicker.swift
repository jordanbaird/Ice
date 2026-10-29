//
//  MenuBarShapePicker.swift
//  Ice
//

import SwiftUI

struct MenuBarShapePicker: View {
    @EnvironmentObject var appearanceManager: MenuBarAppearanceManager
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        shapeKindPicker
        cornerRadiusSlider
        exampleView
    }

    @ViewBuilder
    private var shapeKindPicker: some View {
        IcePicker("Shape Kind", selection: appearanceManager.bindings.configuration.shapeKind) {
            ForEach(MenuBarShapeKind.allCases, id: \.self) { shape in
                switch shape {
                case .none:
                    Text("None").tag(shape)
                case .full:
                    Text("Full").tag(shape)
                case .split:
                    Text("Split").tag(shape)
                }
            }
        }
    }

    @ViewBuilder
    private var cornerRadiusSlider: some View {
        if appearanceManager.configuration.shapeKind != .none,
           appearanceManager.configuration.hasRoundedShape
        {
            IceLabeledContent("Corner Radius") {
                HStack {
                    Slider(value: appearanceManager.bindings.configuration.cornerRadius, in: 0...1)
                    Text("\(Int((appearanceManager.configuration.cornerRadius * 100).rounded()))%")
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 40, alignment: .trailing)
                }
            }
        }
    }

    @ViewBuilder
    private var exampleView: some View {
        switch appearanceManager.configuration.shapeKind {
        case .none:
            Text("No shape kind selected")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
        case .full:
            MenuBarFullShapeExampleView(
                info: appearanceManager.bindings.configuration.fullShapeInfo,
                cornerRadiusFactor: appearanceManager.configuration.cornerRadius
            )
                .equatable()
                .foregroundStyle(colorScheme == .dark ? .primary : .secondary)
        case .split:
            MenuBarSplitShapeExampleView(
                info: appearanceManager.bindings.configuration.splitShapeInfo,
                cornerRadiusFactor: appearanceManager.configuration.cornerRadius
            )
                .equatable()
                .foregroundStyle(colorScheme == .dark ? .primary : .secondary)
        }
    }
}

private struct MenuBarFullShapeExampleView: View, Equatable {
    @Binding var info: MenuBarFullShapeInfo
    var cornerRadiusFactor: Double = 1

    var body: some View {
        VStack {
            pickerStack
            exampleStack
        }
    }

    @ViewBuilder
    private var pickerStack: some View {
        HStack(spacing: 0) {
            leadingEndCapPicker
            Spacer()
            trailingEndCapPicker
        }
        .labelsHidden()
        .pickerStyle(.segmented)
    }

    @ViewBuilder
    private var exampleStack: some View {
        HStack(spacing: 0) {
            leadingEndCapExample
            Rectangle()
            trailingEndCapExample
        }
        .frame(height: 24)
    }

    @ViewBuilder
    private func endCapPickerContentView(endCap: MenuBarEndCap, edge: HorizontalEdge) -> some View {
        switch endCap {
        case .square:
            Image(size: CGSize(width: 12, height: 12)) { context in
                context.fill(Path(context.clipBoundingRect), with: .foreground)
            }
            .resizable()
            .help("Square Cap")
            .tag(endCap)
        case .round:
            Image(size: CGSize(width: 12, height: 12)) { context in
                let remainder = context.clipBoundingRect
                    .divided(atDistance: context.clipBoundingRect.width / 2, from: cgRectEdge(for: edge))
                    .remainder
                let path1 = Path(remainder)
                let path2 = Path(ellipseIn: context.clipBoundingRect)
                context.fill(path1.union(path2), with: .foreground)
            }
            .resizable()
            .help("Round Cap")
            .tag(endCap)
        }
    }

    @ViewBuilder
    private var leadingEndCapPicker: some View {
        Picker("Leading End Cap", selection: $info.leadingEndCap) {
            ForEach(MenuBarEndCap.allCases.reversed(), id: \.self) { endCap in
                endCapPickerContentView(endCap: endCap, edge: .leading)
            }
        }
        .fixedSize()
    }

    @ViewBuilder
    private var trailingEndCapPicker: some View {
        Picker("Trailing End Cap", selection: $info.trailingEndCap) {
            ForEach(MenuBarEndCap.allCases, id: \.self) { endCap in
                endCapPickerContentView(endCap: endCap, edge: .trailing)
            }
        }
        .fixedSize()
    }

    @ViewBuilder
    private var leadingEndCapExample: some View {
        MenuBarEndCapExampleView(
            endCap: info.leadingEndCap,
            edge: .leading,
            cornerRadiusFactor: cornerRadiusFactor
        )
    }

    @ViewBuilder
    private var trailingEndCapExample: some View {
        MenuBarEndCapExampleView(
            endCap: info.trailingEndCap,
            edge: .trailing,
            cornerRadiusFactor: cornerRadiusFactor
        )
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.info == rhs.info && lhs.cornerRadiusFactor == rhs.cornerRadiusFactor
    }

    private func cgRectEdge(for edge: HorizontalEdge) -> CGRectEdge {
        switch edge {
        case .leading: .minXEdge
        case .trailing: .maxXEdge
        }
    }
}

private struct MenuBarEndCapExampleView: View {
    @State private var height: CGFloat = 24

    let endCap: MenuBarEndCap
    let edge: HorizontalEdge
    var cornerRadiusFactor: Double = 1

    private var radius: CGFloat {
        height / 2 * CGFloat(cornerRadiusFactor)
    }

    var body: some View {
        switch endCap {
        case .square:
            Rectangle()
        case .round:
            switch edge {
            case .leading:
                UnevenRoundedRectangle(
                    topLeadingRadius: radius,
                    bottomLeadingRadius: radius,
                    style: .circular
                )
                .onFrameChange { frame in
                    height = frame.height
                }
            case .trailing:
                UnevenRoundedRectangle(
                    bottomTrailingRadius: radius,
                    topTrailingRadius: radius,
                    style: .circular
                )
                .onFrameChange { frame in
                    height = frame.height
                }
            }
        }
    }
}

private struct MenuBarSplitShapeExampleView: View, Equatable {
    @Binding var info: MenuBarSplitShapeInfo
    var cornerRadiusFactor: Double = 1

    var body: some View {
        HStack {
            MenuBarFullShapeExampleView(info: $info.leading, cornerRadiusFactor: cornerRadiusFactor)
                .equatable()
            Divider()
                .padding(.horizontal)
            MenuBarFullShapeExampleView(info: $info.trailing, cornerRadiusFactor: cornerRadiusFactor)
                .equatable()
        }
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.info == rhs.info && lhs.cornerRadiusFactor == rhs.cornerRadiusFactor
    }
}
