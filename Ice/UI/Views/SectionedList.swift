//
//  SectionedList.swift
//  Ice
//

import SwiftUI

// MARK: - SectionedList

/// A scrollable list of items broken up by section.
struct SectionedList<ItemID: Hashable>: View {
    private enum ScrollDirection {
        case up, down
    }

    @Binding var selection: ItemID?

    @Binding var items: [SectionedListItem<ItemID>]

    @State private var itemFrames = [ItemID: CGRect]()

    @State private var scrollIndicatorsFlashTrigger = 0

    let spacing: CGFloat

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

    /// Creates a sectioned list with the given selection, spacing, and items.
    init(selection: Binding<ItemID?>, items: Binding<[SectionedListItem<ItemID>]>, spacing: CGFloat = 0) {
        self._selection = selection
        self._items = items
        self.spacing = spacing
    }

    var body: some View {
        if #available(macOS 15.0, *) {
            scrollView
                .contentMargins(.all, contentPadding, for: .scrollContent)
                .contentMargins(.all, -0.5, for: .scrollIndicators)
        } else {
            scrollView
                .contentMargins(.all, contentPadding, for: .scrollContent)
                .contentMargins(.all, -contentPadding, for: .scrollIndicators)
        }
    }

    @ViewBuilder
    private var scrollView: some View {
        ScrollViewReader { scrollView in
            GeometryReader { geometry in
                ScrollView {
                    scrollContent(scrollView: scrollView, geometry: geometry)
                }
            }
        }
        .scrollIndicatorsFlash(trigger: scrollIndicatorsFlashTrigger)
        .onKeyDown(key: .downArrow, isEnabled: selection != nil) {
            DispatchQueue.main.async {
                if let nextSelectableItem {
                    selection = nextSelectableItem.id
                }
            }
            return .handled
        }
        .onKeyDown(key: .upArrow, isEnabled: selection != nil) {
            DispatchQueue.main.async {
                if let previousSelectableItem {
                    selection = previousSelectableItem.id
                }
            }
            return .handled
        }
        .onKeyDown(key: .return, isEnabled: selection != nil) {
            DispatchQueue.main.async {
                items.first { $0.id == selection }?.action?()
            }
            return .handled
        }
        .task {
            scrollIndicatorsFlashTrigger += 1
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
        withMutableCopy(of: self) { copy in
            copy.contentPadding = insets
        }
    }

    /// Sets the padding of the sectioned list's content.
    func contentPadding(_ length: CGFloat) -> SectionedList {
        contentPadding(EdgeInsets(top: length, leading: length, bottom: length, trailing: length))
    }
}

// MARK: - SectionedListItem

/// An item in a sectioned list.
struct SectionedListItem<ID: Hashable> {
    let content: AnyView
    let id: ID
    let isSelectable: Bool
    let action: (() -> Void)?

    /// Returns a selectable item for a sectioned list.
    static func item(id: ID, isSelectable: Bool = true, action: (() -> Void)? = nil, @ViewBuilder content: () -> some View) -> SectionedListItem {
        SectionedListItem(content: AnyView(content()), id: id, isSelectable: isSelectable, action: action)
    }

    /// Returns a section header item for a sectioned list.
    static func header(id: ID, @ViewBuilder content: () -> some View) -> SectionedListItem {
        item(id: id, isSelectable: false, action: nil) {
            content()
        }
    }
}

// MARK: - SectionedListItemView

private struct SectionedListItemView<ItemID: Hashable>: View {
    @Environment(\.self) private var environment
    @Binding var selection: ItemID?
    @Binding var itemFrames: [ItemID: CGRect]
    @State private var isHovering = false

    let item: SectionedListItem<ItemID>

    private var foregroundStyle: some ShapeStyle {
        if
            environment.colorScheme == .light,
            selection == item.id
        {
            Color.primary.resolve(in: withMutableCopy(of: environment) { $0.colorScheme = .dark })
        } else {
            Color.primary.resolve(in: environment)
        }
    }

    private var backgroundShape: some InsettableShape {
        if #available(macOS 26.0, *) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
        } else {
            RoundedRectangle(cornerRadius: 5, style: .circular)
        }
    }

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
                .foregroundStyle(foregroundStyle)
        }
        .frame(minWidth: 22, minHeight: 22)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
        }
        .onTapGesture {
            selection = item.id
        }
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                item.action?()
            }
        )
        .onFrameChange(in: .global) { frame in
            itemFrames[item.id] = frame
        }
    }

    @ViewBuilder
    private var itemBackground: some View {
        if #available(macOS 26.0, *) {
            backgroundShape
                .fill(.tint)
        } else {
            VisualEffectView(material: .selection, blendingMode: .withinWindow)
                .clipShape(backgroundShape)
        }
    }
}
