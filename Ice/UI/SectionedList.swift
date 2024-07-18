//
//  SectionedList.swift
//  Ice
//

import SwiftUI

// MARK: - SectionedList

struct SectionedList<ItemID: Hashable>: View {
    private enum ScrollDirection {
        case up, down
    }

    @Binding var selection: ItemID?
    @State private var itemFrames = [ItemID: CGRect]()

    let spacing: CGFloat
    let items: [SectionedListItem<ItemID>]
    private(set) var contentPadding = EdgeInsets()

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
        items: [SectionedListItem<ItemID>]
    ) {
        self._selection = selection
        self.spacing = spacing
        self.items = items
    }

    var body: some View {
        ScrollViewReader { scrollView in
            GeometryReader { geometry in
                ScrollView {
                    scrollContent(scrollView: scrollView, geometry: geometry)
                }
                .padding(.top, contentPadding.top)
                .padding(.bottom, contentPadding.bottom)
                .contentMargins(.top, -contentPadding.top, for: .scrollIndicators)
                .contentMargins(.bottom, -contentPadding.bottom, for: .scrollIndicators)
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
        .padding(.leading, contentPadding.leading)
        .padding(.trailing, contentPadding.trailing)
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
        if selectionFrame.minY <= geometryFrame.minY + contentPadding.top {
            return .up
        }
        if selectionFrame.maxY >= geometryFrame.maxY - contentPadding.bottom {
            return .down
        }
        return nil
    }
}

// MARK: SectionedList Content Padding
extension SectionedList {
    /// Sets the padding of the sectioned list's content.
    func contentPadding(_ insets: EdgeInsets) -> SectionedList {
        with(self) { copy in
            copy.contentPadding = insets
        }
    }

    /// Sets the padding of the sectioned list's content.
    func contentPadding(_ length: CGFloat) -> SectionedList {
        contentPadding(EdgeInsets(top: length, leading: length, bottom: length, trailing: length))
    }
}

// MARK: - SectionedListItem

struct SectionedListItem<ID: Hashable> {
    let content: AnyView
    let id: ID
    let isSelectable: Bool
    let action: (() -> Void)?

    static func item(id: ID, isSelectable: Bool = true, action: (() -> Void)? = nil, @ViewBuilder content: () -> some View) -> SectionedListItem {
        SectionedListItem(content: AnyView(content()), id: id, isSelectable: isSelectable, action: action)
    }

    static func header(id: ID, @ViewBuilder content: () -> some View) -> SectionedListItem {
        item(id: id, isSelectable: false, action: nil) {
            content()
        }
    }
}

// MARK: - SectionedListItemView

private struct SectionedListItemView<ItemID: Hashable>: View {
    @Binding var selection: ItemID?
    @Binding var itemFrames: [ItemID: CGRect]
    @State private var isHovering = false

    let item: SectionedListItem<ItemID>

    var body: some View {
        ZStack {
            if item.isSelectable {
                if selection == item.id {
                    itemBackground.opacity(0.5)
                } else if isHovering {
                    itemBackground.opacity(0.25)
                }
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
    }
}
