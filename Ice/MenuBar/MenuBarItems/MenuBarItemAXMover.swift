//
//  MenuBarItemAXMover.swift
//  Ice
//

import Carbon.HIToolbox
import Cocoa

/// Moves a menu bar item by simulating the user's Command-drag.
///
/// Ice's old move pipeline needed a CGS window (windowID, ownerPID, frame change),
/// so it no longer works on macOS 27. This approach only needs the icon's
/// on-screen position plus Accessibility permission — exactly what the user
/// would do by hand, so the system still honors it.
///
/// Quartz coordinates (origin top-left, same system as `CGEvent.location`,
/// `WindowInfo.frame`, and `AXUIElement` frames) — do NOT use Cocoa coordinates
/// (origin bottom-left) here; mixing them up drops the item in the wrong spot
/// and a rescan then shows the old position (looking like it "snapped back").
enum MenuBarItemAXMover {
    /// Drags from `source` to `destination` while holding Command.
    ///
    /// Quartz coordinates (origin top-left). Runs in the background, takes well
    /// under a second. The cursor stays visible and is returned to its original
    /// spot; the Command key is always released (even if event creation fails
    /// midway).
    static func commandDrag(from source: CGPoint, to destination: CGPoint) async {
        await Task.detached(priority: .userInitiated) {
            guard let eventSource = CGEventSource(stateID: .hidSystemState) else {
                return
            }
            // Ignore the real mouse while the drag runs: the user's hand is often
            // still moving right after dropping in Settings, and a real move
            // between synthetic events yanks the dragged icon off course.
            // Keyboard and system events stay allowed.
            let keepEvents: CGEventFilterMask = [.permitLocalKeyboardEvents, .permitSystemDefinedEvents]
            eventSource.setLocalEventsFilterDuringSuppressionState(keepEvents, state: .eventSuppressionStateSuppressionInterval)
            eventSource.setLocalEventsFilterDuringSuppressionState(keepEvents, state: .eventSuppressionStateRemoteMouseDrag)
            eventSource.localEventsSuppressionInterval = 0.3

            // Remember the old cursor position to restore after the drag. Don't hide
            // the cursor: a disappearing cursor makes users think the app hung.
            let originalLocation = CGEvent(source: nil)?.location
            defer {
                if let originalLocation {
                    CGWarpMouseCursorPosition(originalLocation)
                }
            }

            func post(_ type: CGEventType, at point: CGPoint, flags: CGEventFlags) {
                guard
                    let event = CGEvent(
                        mouseEventSource: eventSource,
                        mouseType: type,
                        mouseCursorPosition: point,
                        mouseButton: .left
                    )
                else {
                    return
                }
                event.flags = flags
                event.post(tap: .cghidEventTap)
            }

            // A mouse event can't be a flagsChanged event (creating one returns
            // nil), so Command goes down and up as the real key.
            func postCommand(down: Bool) {
                guard
                    let event = CGEvent(
                        keyboardEventSource: eventSource,
                        virtualKey: CGKeyCode(kVK_Command),
                        keyDown: down
                    )
                else {
                    return
                }
                event.type = .flagsChanged
                event.flags = down ? .maskCommand : []
                event.post(tap: .cghidEventTap)
            }

            // Release Command on exit no matter what happens below.
            var didPressCommand = false
            defer {
                if didPressCommand {
                    postCommand(down: false)
                }
            }

            // Move the cursor onto the icon first so the system "sees" the start point.
            post(.mouseMoved, at: source, flags: [])
            try? await Task.sleep(for: .milliseconds(120))

            // Hold Command, as the user would.
            postCommand(down: true)
            didPressCommand = true
            try? await Task.sleep(for: .milliseconds(80))

            post(.leftMouseDown, at: source, flags: .maskCommand)
            try? await Task.sleep(for: .milliseconds(120))

            // ponytail: 15 steps are enough for the system to register the drag;
            // 30 steps as before only prolong the cursor freeze.
            let steps = 15
            for index in 1...steps {
                let progress = CGFloat(index) / CGFloat(steps)
                let point = CGPoint(
                    x: source.x + (destination.x - source.x) * progress,
                    y: source.y + (destination.y - source.y) * progress
                )
                post(.leftMouseDragged, at: point, flags: .maskCommand)
                try? await Task.sleep(for: .milliseconds(15))
            }

            // Hover on the drop point before letting go. The menu bar slides
            // icons aside while they're dragged past; releasing 15ms after
            // arriving sometimes dropped against the half-finished layout, so
            // the icon landed short and the drag had to be redone.
            for _ in 0..<3 {
                post(.leftMouseDragged, at: destination, flags: .maskCommand)
                try? await Task.sleep(for: .milliseconds(50))
            }

            post(.leftMouseUp, at: destination, flags: .maskCommand)
            try? await Task.sleep(for: .milliseconds(150))

            // Release Command and wait for the system to commit the new position
            // before restoring the cursor.
            postCommand(down: false)
            didPressCommand = false
            try? await Task.sleep(for: .milliseconds(350))
        }.value
    }
}
