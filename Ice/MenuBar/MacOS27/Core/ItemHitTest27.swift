//
//  ItemHitTest27.swift
//  Ice
//

import CoreGraphics
import Darwin

/// Decides whether the pointer rests on a menu bar item on macOS 27.
///
/// There are no item windows on macOS 27, so the test uses the Accessibility
/// frames Ice cached for the drawn items, plus the system items and the overflow
/// button. Accessibility reports frames only for the active menu bar, so on the
/// other display every spot counts as empty, as it did in earlier versions of Ice.
enum ItemHitTest27 {
    struct Item: Equatable {
        let frame: CGRect
        let ownerPID: pid_t
        let isOnScreen: Bool
    }

    /// Whether the pointer rests in the part of the bar that holds items, gaps included.
    ///
    /// The gaps between items are not empty bar: hovering them must not reveal a section,
    /// because the whole right-hand run of icons belongs to the items. The area starts at
    /// the leftmost thing drawn on this display and reaches its right edge. Frames left
    /// behind on the other display are ignored. The edge remembered from the last read counts
    /// alongside the frames Ice has cached, because that cache holds only the items Ice
    /// manages: the run of the bar can start further left than anything in it. Only items
    /// that are drawn feed that edge, so the space a concealed section frees is not swallowed.
    static func isInsideItemsArea(
        point: CGPoint,
        displayBounds: CGRect,
        items: [Item],
        concealedPIDs: Set<pid_t>,
        systemFrames: [CGRect],
        rememberedLeftEdge: CGFloat?
    ) -> Bool {
        guard displayBounds.minX...displayBounds.maxX ~= point.x else {
            return false
        }
        func isOnThisDisplay(_ frame: CGRect) -> Bool {
            frame.minX >= displayBounds.minX && frame.minX <= displayBounds.maxX
        }
        var edges = items
            .filter { $0.isOnScreen && !concealedPIDs.contains($0.ownerPID) && isOnThisDisplay($0.frame) }
            .map(\.frame.minX)
        edges += systemFrames.filter(isOnThisDisplay).map(\.minX)
        if let remembered = rememberedLeftEdge, displayBounds.minX...displayBounds.maxX ~= remembered {
            edges.append(remembered)
        }
        guard let leftEdge = edges.min() else {
            return false
        }
        return point.x >= leftEdge
    }

    static func isInsideItem(point: CGPoint, items: [Item], concealedPIDs: Set<pid_t>, systemFrames: [CGRect]) -> Bool {
        let isInsideDrawnItem = items.contains { item in
            item.isOnScreen && !concealedPIDs.contains(item.ownerPID) && item.frame.contains(point)
        }
        return isInsideDrawnItem || systemFrames.contains { $0.contains(point) }
    }
}
