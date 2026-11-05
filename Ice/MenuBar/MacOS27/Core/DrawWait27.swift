//
//  DrawWait27.swift
//  Ice
//

import CoreGraphics
import Foundation

/// Decides where an item is while Ice waits for it to be drawn on macOS 27.
///
/// Showing an application through the native switch takes a moment, and the item does not
/// always arrive where it can be seen. Four things can be true of it, and the caller does
/// something different for each, so the reading of them belongs in one tested place.
///
/// What makes absence meaningful is timing. An item the bar has room for is published 0.52
/// to 0.61 s after its application is allowed (measured 2026-11-04 over five clicks). An item
/// folded into the system overflow is published by nobody at all — its own application answers
/// `kAXErrorNoValue` for as long as it stays folded (measured the same day on Docker Desktop,
/// through a 4.5 s wait, while the overflow control stood on the bar beside it). So an item
/// still missing once one would have arrived, on a bar that shows a collapsed overflow
/// control, is folded into it, and the caller can act instead of waiting out the timeout.
enum DrawWait27 {
    struct Input {
        /// How long since the application was shown.
        var elapsed: Duration
        /// The shortest wait before anything counts. Assessment mode leaves a concealed item
        /// in Accessibility's account of the bar at the frame it last had, which would read
        /// as drawn the moment the application is shown.
        var floor: Duration
        /// The longest wait before the caller is answered with nothing.
        var timeout: Duration
        /// When an item missing altogether counts as folded rather than merely slow.
        var foldedVerdict: Duration
        /// Frames of the wanted item that count as drawn (see ``ItemDrawing27``).
        var drawnFrames: [CGRect]
        /// Its other frames: published, but not drawn anywhere.
        var undrawnFrames: [CGRect]
        /// Below this an item is a sliver rather than something a person can see or click.
        /// A sliver still counts as published, so a bar carrying one is not hiding the item
        /// in its overflow — Ice keeps waiting instead of expanding it for nothing.
        var minimumWidth: CGFloat
        /// The span the active display's notch covers, or `nil` where it has none.
        var notchXRange: ClosedRange<CGFloat>?
        /// The bounds of the display whose menu bar is active.
        var activeDisplayBounds: CGRect?
        /// Whether that display's bar shows a collapsed system overflow control.
        var hasCollapsedOverflow: Bool
        /// Whether a frame across the notch ends the wait. It does for a freshly shown
        /// application, which is put back where MenuBarAgent last had it and stays there. It
        /// does not right after the overflow is expanded, where that is merely where the item
        /// was while it was folded: it is laid out afresh a moment later (measured 2026-11-04:
        /// 0.17 s, from x=-834 across the notch to x=-1084 beside it).
        var acrossNotchIsFinal: Bool
    }

    enum Verdict: Equatable {
        case keepWaiting
        /// The index into `drawnFrames` of the item that is drawn.
        ///
        /// An index, not the frame: the caller has to get back the item it asked about, and
        /// finding it again by frame equality can hand back a different item of the same
        /// application that happens to share a frame, or nothing at all when a frame carries
        /// a NaN and cannot be compared with itself.
        case drawn(index: Int)
        case folded
        case acrossNotch(CGRect)
        case timedOut
    }

    static func verdict(_ input: Input) -> Verdict {
        guard input.elapsed >= input.floor else {
            return .keepWaiting
        }
        if let drawn = input.drawnFrames.firstIndex(where: { $0.width > input.minimumWidth }) {
            return .drawn(index: drawn)
        }
        if
            input.elapsed >= input.foldedVerdict,
            input.hasCollapsedOverflow,
            input.drawnFrames.isEmpty,
            input.undrawnFrames.isEmpty
        {
            return .folded
        }
        if
            input.acrossNotchIsFinal,
            let notchXRange = input.notchXRange,
            let acrossNotch = input.undrawnFrames.first(where: { frame in
                frame.width > input.minimumWidth
                    && frame.minX < notchXRange.upperBound
                    && frame.maxX > notchXRange.lowerBound
                    && (input.activeDisplayBounds?.intersects(frame) ?? true)
            })
        {
            return .acrossNotch(acrossNotch)
        }
        if input.elapsed >= input.timeout {
            return .timedOut
        }
        return .keepWaiting
    }
}
