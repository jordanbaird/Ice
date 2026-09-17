//
//  MenuBarShapePicker.swift
//  Ice
//

import SwiftUI

struct MenuBarShapePicker: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var configuration: MenuBarAppearanceConfigurationV2

    var body: some View {
        VStack {
            shapeKindPicker
            shapePicker
                .foregroundStyle(colorScheme == .dark ? .primary : .secondary)
        }
        if configuration.shapeKind == .noShape {
            Text("No shape kind selected")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    @ViewBuilder
    private var shapeKindPicker: some View {
        IcePicker("Shape Kind", selection: $configuration.shapeKind) {
            ForEach(MenuBarShapeKind.allCases) { shapeKind in
                Text(shapeKind.localized).tag(shapeKind)
            }
        }
    }

    @ViewBuilder
    private var shapePicker: some View {
        switch configuration.shapeKind {
        case .noShape:
            EmptyView()
        case .full:
            MenuBarFullShapePicker(info: $configuration.fullShapeInfo).equatable()
        case .split:
            MenuBarSplitShapePicker(info: $configuration.splitShapeInfo).equatable()
        }
    }
}

private struct MenuBarFullShapePicker: View, Equatable {
    @Binding var info: MenuBarFullShapeInfo

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
            edge: .leading
        )
    }

    @ViewBuilder
    private var trailingEndCapExample: some View {
        MenuBarEndCapExampleView(
            endCap: info.trailingEndCap,
            edge: .trailing
        )
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.info == rhs.info
    }

    private func cgRectEdge(for edge: HorizontalEdge) -> CGRectEdge {
        switch edge {
        case .leading: .minXEdge
        case .trailing: .maxXEdge
        }
    }
}

private struct MenuBarSplitShapePicker: View, Equatable {
    @Binding var info: MenuBarSplitShapeInfo

    var body: some View {
        HStack {
            MenuBarFullShapePicker(info: $info.leading).equatable()
            Divider()
            MenuBarFullShapePicker(info: $info.trailing).equatable()
        }
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.info == rhs.info
    }
}

private struct MenuBarEndCapExampleView: View {
    @State private var radius: CGFloat = 0

    let endCap: MenuBarEndCap
    let edge: HorizontalEdge

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
                    radius = frame.height / 2
                }
            case .trailing:
                UnevenRoundedRectangle(
                    bottomTrailingRadius: radius,
                    topTrailingRadius: radius,
                    style: .circular
                )
                .onFrameChange { frame in
                    radius = frame.height / 2
                }
            }
        }
    }
}
