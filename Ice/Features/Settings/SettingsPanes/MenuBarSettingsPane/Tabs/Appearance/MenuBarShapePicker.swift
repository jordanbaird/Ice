//
//  MenuBarShapePicker.swift
//  Ice
//

import SwiftUI

struct MenuBarShapePicker: View {
    @EnvironmentObject var appState: AppState

    private var menuBar: MenuBar {
        appState.menuBar
    }

    var body: some View {
        shapeKindPicker
        shapeExample
    }

    @ViewBuilder
    private var shapeKindPicker: some View {
        Picker("Kind", selection: menuBar.bindings.shapeKind) {
            ForEach(MenuBarShapeKind.allCases, id: \.self) { shape in
                switch shape {
                case .full:
                    Text("Full").tag(shape)
                case .split:
                    Text("Split").tag(shape)
                }
            }
        }
    }

    @ViewBuilder
    private var shapeExample: some View {
        switch menuBar.shapeKind {
        case .full:
            MenuBarFullShapeExample(info: menuBar.bindings.fullShapeInfo)
        case .split:
            MenuBarSplitShapeExample(info: menuBar.bindings.splitShapeInfo)
        }
    }
}

private struct MenuBarFullShapeExample: View {
    @Binding var info: MenuBarFullShapeInfo
    @State private var leadingEndCapRadius: CGFloat = 0
    @State private var trailingEndCapRadius: CGFloat = 0

    var body: some View {
        VStack {
            pickerStack
            shapeStack
        }
    }

    @ViewBuilder
    private var pickerStack: some View {
        HStack(spacing: 0) {
            leadingEndCapPicker
            Spacer()
            trailingEndCapPicker
        }
    }

    @ViewBuilder
    private var shapeStack: some View {
        HStack(spacing: 0) {
            leadingEndCap
            Rectangle()
            trailingEndCap
        }
        .frame(height: 24)
    }

    @ViewBuilder
    private func endCapView(for endCap: MenuBarEndCap, edge: CGRectEdge) -> some View {
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
                let half = context.clipBoundingRect
                    .divided(
                        atDistance: context.clipBoundingRect.width / 2,
                        from: edge
                    )
                    .remainder
                context.fill(Path(half), with: .color(.black))
                context.fill(Path(ellipseIn: context.clipBoundingRect), with: .color(.black))
            }
            .renderingMode(.template)
            .resizable()
            .help("Round Cap")
        }
    }

    @ViewBuilder
    private var leadingEndCapPicker: some View {
        Picker("Leading End Cap", selection: $info.leadingEndCap) {
            ForEach(MenuBarEndCap.allCases.reversed(), id: \.self) { endCap in
                endCapView(for: endCap, edge: .minXEdge).tag(endCap)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
    }

    @ViewBuilder
    private var leadingEndCap: some View {
        switch info.leadingEndCap {
        case .square:
            Rectangle()
        case .round:
            UnevenRoundedRectangle(
                topLeadingRadius: leadingEndCapRadius,
                bottomLeadingRadius: leadingEndCapRadius,
                style: .circular
            )
            .onFrameChange { frame in
                leadingEndCapRadius = frame.height / 2
            }
        }
    }

    @ViewBuilder
    private var trailingEndCapPicker: some View {
        Picker("Trailing End Cap", selection: $info.trailingEndCap) {
            ForEach(MenuBarEndCap.allCases, id: \.self) { endCap in
                endCapView(for: endCap, edge: .maxXEdge).tag(endCap)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
    }

    @ViewBuilder
    private var trailingEndCap: some View {
        switch info.trailingEndCap {
        case .square:
            Rectangle()
        case .round:
            UnevenRoundedRectangle(
                bottomTrailingRadius: trailingEndCapRadius,
                topTrailingRadius: trailingEndCapRadius,
                style: .circular
            )
            .onFrameChange { frame in
                trailingEndCapRadius = frame.height / 2
            }
        }
    }
}

private struct MenuBarSplitShapeExample: View {
    @Binding var info: MenuBarSplitShapeInfo

    var body: some View {
        HStack {
            MenuBarFullShapeExample(info: $info.leading)
            Divider()
                .padding(.horizontal)
            MenuBarFullShapeExample(info: $info.trailing)
        }
    }
}
