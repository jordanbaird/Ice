//
//  MenuBarShapePicker.swift
//  Ice
//

import SwiftUI

struct MenuBarShapePicker: View {
    @EnvironmentObject var appState: AppState

    private var appearanceManager: MenuBarAppearanceManager {
        appState.menuBarManager.appearanceManager
    }

    var body: some View {
        shapeKindPicker
        exampleView
    }

    @ViewBuilder
    private var shapeKindPicker: some View {
        Picker("Shape Kind", selection: appearanceManager.bindings.shapeKind) {
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
    private var exampleView: some View {
        switch appearanceManager.shapeKind {
        case .none:
            Text("No shape kind selected")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
        case .full:
            MenuBarFullShapeExampleView(info: appearanceManager.bindings.fullShapeInfo)
                .equatable()
        case .split:
            MenuBarSplitShapeExampleView(info: appearanceManager.bindings.splitShapeInfo)
                .equatable()
        }
    }
}

private struct MenuBarFullShapeExampleView: View, Equatable {
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
    private var leadingEndCapPicker: some View {
        Picker("Leading End Cap", selection: $info.leadingEndCap) {
            ForEach(MenuBarEndCap.allCases.reversed(), id: \.self) { endCap in
                MenuBarEndCapPickerContentView(
                    endCap: endCap,
                    edge: .leading
                )
                .equatable()
                .tag(endCap)
            }
        }
        .fixedSize()
    }

    @ViewBuilder
    private var trailingEndCapPicker: some View {
        Picker("Trailing End Cap", selection: $info.trailingEndCap) {
            ForEach(MenuBarEndCap.allCases, id: \.self) { endCap in
                MenuBarEndCapPickerContentView(
                    endCap: endCap,
                    edge: .trailing
                )
                .equatable()
                .tag(endCap)
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
        .equatable()
    }

    @ViewBuilder
    private var trailingEndCapExample: some View {
        MenuBarEndCapExampleView(
            endCap: info.trailingEndCap,
            edge: .trailing
        )
        .equatable()
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.info == rhs.info
    }
}

private struct MenuBarEndCapPickerContentView: View, Equatable {
    let endCap: MenuBarEndCap
    let edge: HorizontalEdge

    var body: some View {
        switch endCap {
        case .square:
            Image(size: CGSize(width: 12, height: 12)) { context in
                context.fill(Path(context.clipBoundingRect), with: .color(.black))
            }
            .renderingMode(.template)
            .resizable()
            .help("Square Cap")
        case .round:
            Image(size: CGSize(width: 12, height: 12)) { context in
                let remainder = context.clipBoundingRect
                    .divided(
                        atDistance: context.clipBoundingRect.width / 2,
                        from: edge.cgRectEdge
                    )
                    .remainder
                let paths: [Path] = [
                    Path(remainder),
                    Path(ellipseIn: context.clipBoundingRect),
                ]
                for path in paths {
                    context.fill(path, with: .color(.black))
                }
            }
            .renderingMode(.template)
            .resizable()
            .help("Round Cap")
        }
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.endCap == rhs.endCap &&
        lhs.edge == rhs.edge
    }
}

private struct MenuBarEndCapExampleView: View, Equatable {
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

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.radius == rhs.radius &&
        lhs.endCap == rhs.endCap &&
        lhs.edge == rhs.edge
    }
}

private struct MenuBarSplitShapeExampleView: View, Equatable {
    @Binding var info: MenuBarSplitShapeInfo

    var body: some View {
        HStack {
            MenuBarFullShapeExampleView(info: $info.leading)
                .equatable()
            Divider()
                .padding(.horizontal)
            MenuBarFullShapeExampleView(info: $info.trailing)
                .equatable()
        }
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.info == rhs.info
    }
}
