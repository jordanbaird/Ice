//
//  MacOS27NativeBoundary.swift
//  Ice
//

import CoreGraphics

/// Defers Ice-owned visibility mutations while a native drag is holding its
/// source/target scenes. Only the need to resync is retained, never old intent.
struct MacOS27NativeDragVisibilityState {
    private var dragDepth = 0
    private var hasPendingUpdate = false

    mutating func beginDrag() {
        dragDepth += 1
    }

    mutating func shouldApplyVisibilityUpdate() -> Bool {
        guard dragDepth > 0 else { return true }
        hasPendingUpdate = true
        return false
    }

    /// Returns whether the caller must reread current visibility/Layout state.
    mutating func endDrag() -> Bool {
        guard dragDepth > 0 else { return false }
        dragDepth -= 1
        guard dragDepth == 0 else { return false }
        defer { hasPendingUpdate = false }
        return hasPendingUpdate
    }
}

/// The visible Ice button, not a saved assignment or an invisible slot, is the
/// user-facing boundary. Keep these decisions independent of event handling.
enum MacOS27NativeBoundary {
    enum Side {
        case left, right
    }

    /// Conservative quick-path geometry for the native narrow handle. This
    /// is only for resizing our own item, never for targeting mouse input.
    /// Callers reject ambiguous owner variants and recheck frames. Wider gaps,
    /// custom spacing and unsettled frames use the full ordering check.
    static func canCheckImmediateHide(boundary: CGRect, control: CGRect, display: CGRect) -> Bool {
        let geometry = [
            boundary.minX, boundary.minY, boundary.width, boundary.height,
            control.minX, control.minY, control.width, control.height,
        ]
        guard geometry.allSatisfy(\.isFinite),
              canDrag(from: boundary, to: control, on: display),
              boundary.width <= 3, abs(boundary.midY - control.midY) < 0.5 else { return false }
        let gap = control.minX - boundary.maxX
        return gap >= 0 && gap <= 6
    }

    static func side(of frame: CGRect, relativeTo control: CGRect) -> Side? {
        guard frame.width > 0, frame.height > 0, control.width > 0,
              abs(frame.midY - control.midY) < min(frame.height, control.height) / 2,
              frame.minX != control.minX else { return nil }
        // Hosted hit areas may overlap at their edges after a valid drop.
        // Left-to-right order is determined by origins, not touching edges.
        return frame.minX < control.minX ? .left : .right
    }

    /// Overflow AX elements may retain frames below the display. Never send
    /// a native drag to those coordinates or across unrelated display rows.
    static func canDrag(from source: CGRect, to target: CGRect, on display: CGRect) -> Bool {
        let strip = CGRect(x: display.minX, y: display.minY, width: display.width, height: 40)
        return side(of: source, relativeTo: target) != nil &&
            strip.contains(source) && strip.contains(target)
    }

    static func isImmediatelyBefore<Item: Equatable>(
        _ boundary: Item, _ control: Item, in order: [Item]
    ) -> Bool {
        guard let boundaryIndex = order.firstIndex(of: boundary),
              let controlIndex = order.firstIndex(of: control) else { return false }
        return boundaryIndex + 1 == controlIndex
    }
}
