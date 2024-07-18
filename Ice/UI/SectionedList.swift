//
//  SectionedList.swift
//  Ice
//

import SwiftUI

struct SectionedList<ItemID: Hashable>: View {
    private enum ScrollDirection {
        case up, down
    }

    @Binding var selection: ItemID?
    @State private var itemFrames = [ItemID: CGRect]()

    let spacing: CGFloat
    let items: [SectionedListItem<ItemID>]
    let padding: EdgeInsets

    private var nextSelectableItem: SectionedListItem<ItemID>? {
        guard
            let index = items.firstIndex(where: { $0.id == selection }),
            items.indices.contains(index + 1)
        else {
            return nil
        }
        return items[(index + 1)...].first { $0.isSelectable }
    }

    private var previousSelectableItem: SectionedListItem<ItemID>? {
        guard
            let index = items.firstIndex(where: { $0.id == selection }),
            items.indices.contains(index - 1)
        else {
            return nil
        }
        return items[...(index - 1)].last { $0.isSelectable }
    }

    init(
        selection: Binding<ItemID?>,
        spacing: CGFloat = 0,
        padding: EdgeInsets = EdgeInsets(),
        items: [SectionedListItem<ItemID>]
    ) {
        self._selection = selection
        self.spacing = spacing
        self.padding = padding
        self.items = items
    }

    init(
        selection: Binding<ItemID?>,
        spacing: CGFloat = 0,
        horizontalPadding: CGFloat = 0,
        verticalPadding: CGFloat = 0,
        items: [SectionedListItem<ItemID>]
    ) {
        self.init(
            selection: selection,
            spacing: spacing,
            padding: EdgeInsets(
                top: verticalPadding,
                leading: horizontalPadding,
                bottom: verticalPadding,
                trailing: horizontalPadding
            ),
            items: items
        )
    }

    var body: some View {
        ScrollViewReader { scrollView in
            GeometryReader { geometry in
                ScrollView {
                    scrollContent(scrollView: scrollView, geometry: geometry)
                }
                .padding(.top, padding.top)
                .padding(.bottom, padding.bottom)
                .contentMargins(.top, -padding.top, for: .scrollIndicators)
                .contentMargins(.bottom, -padding.bottom, for: .scrollIndicators)
                .scrollClipDisabled()
                .clipped()
            }
        }
    }

    @ViewBuilder
    private func scrollContent(scrollView: ScrollViewProxy, geometry: GeometryProxy) -> some View {
        VStack(spacing: spacing) {
            ForEach(items, id: \.id) { item in
                SectionedListItemView(
                    selection: $selection,
                    itemFrames: $itemFrames,
                    item: item
                )
                .id(item.id)
            }
        }
        .padding(.leading, padding.leading)
        .padding(.trailing, padding.trailing)
        .onKeyDown(key: .downArrow) {
            if let nextSelectableItem {
                selection = nextSelectableItem.id
            }
        }
        .onKeyDown(key: .upArrow) {
            if let previousSelectableItem {
                selection = previousSelectableItem.id
            }
        }
        .onKeyDown(key: .return) {
            items.first { $0.id == selection }?.action?()
        }
        .onChange(of: selection) {
            guard
                let selection,
                let direction = scrollDirection(for: selection, geometry: geometry)
            else {
                return
            }
            let anchor: UnitPoint = switch direction {
            case .up: .top
            case .down: .bottom
            }
            scrollView.scrollTo(selection, anchor: anchor)
        }
    }

    private func scrollDirection(for selection: ItemID, geometry: GeometryProxy) -> ScrollDirection? {
        guard let selectionFrame = itemFrames[selection] else {
            return nil
        }
        let geometryFrame = geometry.frame(in: .global)
        if selectionFrame.maxY >= geometryFrame.maxY - padding.bottom {
            return .down
        }
        if selectionFrame.minY <= geometryFrame.minY + padding.top {
            return .up
        }
        return nil
    }
}

class SectionedListItem<ID: Hashable> {
    let content: AnyView
    let id: ID
    let isSelectable: Bool
    let action: (() -> Void)?

    init(content: AnyView, id: ID, isSelectable: Bool, action: (() -> Void)?) {
        self.content = content
        self.id = id
        self.isSelectable = isSelectable
        self.action = action
    }

    convenience init(isSelectable: Bool, id: ID, action: (() -> Void)?, @ViewBuilder content: () -> some View) {
        self.init(content: AnyView(content()), id: id, isSelectable: isSelectable, action: action)
    }
}

class SectionedListHeaderItem<ID: Hashable>: SectionedListItem<ID> {
    init(content: AnyView, id: ID) {
        super.init(content: content, id: id, isSelectable: false, action: nil)
    }

    convenience init(id: ID, @ViewBuilder content: () -> some View) {
        self.init(content: AnyView(content()), id: id)
    }
}

private struct SectionedListItemView<ItemID: Hashable>: View {
    @Binding var selection: ItemID?
    @Binding var itemFrames: [ItemID: CGRect]
    @State private var isHovering = false

    let item: SectionedListItem<ItemID>

    var body: some View {
        ZStack {
            if item.isSelectable {
                itemBackground
            }
            item.content
        }
        .frame(minWidth: 22, minHeight: 22)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
        }
        .onTapGesture {
            selection = item.id
        }
        .onFrameChange(in: .global) { frame in
            itemFrames[item.id] = frame
        }
    }

    @ViewBuilder
    private var itemBackground: some View {
        VisualEffectView(material: .selection, blendingMode: .withinWindow)
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .circular))
            .opacity(selection == item.id ? 0.5 : isHovering ? 0.25 : 0)
    }
}
