// Compile together with Ice/MenuBar/MenuBarItems/MacOS27NativeBoundary.swift.
import CoreGraphics

@main
enum NativeMenuBarBoundaryTests {
    static func main() {
        var assertions = 0
        func check(_ condition: Bool, _ description: String) {
            precondition(condition, description)
            assertions += 1
            print("PASS: \(description)")
        }
        func frame(_ x: CGFloat, y: CGFloat = 4, width: CGFloat = 28) -> CGRect {
            CGRect(x: x, y: y, width: width, height: 24)
        }
        let ice = frame(300)
        check(MacOS27NativeBoundary.side(of: frame(270), relativeTo: ice) == .left,
              "a hidden item starts on the left of Ice")
        check(MacOS27NativeBoundary.side(of: frame(334), relativeTo: ice) == .right,
              "dragging that item to the right makes it visible")
        check(MacOS27NativeBoundary.side(of: frame(334), relativeTo: ice) == .right,
              "a visible item starts on the right of Ice")
        check(MacOS27NativeBoundary.side(of: frame(270), relativeTo: ice) == .left,
              "dragging that item left makes it hidden, including an empty Hidden section")
        check(MacOS27NativeBoundary.side(of: frame(327), relativeTo: ice) == .right,
              "overlapping AX hit areas do not change native left-to-right order")
        check(MacOS27NativeBoundary.side(of: frame(7, y: 1121), relativeTo: ice) == nil,
              "off-bar overflow frames cannot overwrite a saved section")
        check(MacOS27NativeBoundary.side(of: ice, relativeTo: ice) == nil,
              "coincident transient frames are not treated as a completed drag")
        check(MacOS27NativeBoundary.isImmediatelyBefore("boundary", "ice", in: ["hidden", "boundary", "ice", "visible"]),
              "an aligned boundary needs no synthetic move")
        check(!MacOS27NativeBoundary.isImmediatelyBefore("boundary", "ice", in: ["hidden", "boundary", "dropped", "ice", "visible"]),
              "a drop between the blank and Ice requires moving only the blank")
        check(MacOS27NativeBoundary.isImmediatelyBefore("boundary", "ice", in: ["hidden", "dropped", "boundary", "ice", "visible"]),
              "after correction every item left of Ice is also left of the hiding boundary")
        check(!MacOS27NativeBoundary.isImmediatelyBefore("boundary", "ice", in: ["hidden", "ice", "boundary", "visible"]),
              "a boundary on the wrong side of Ice cannot be accepted")
        check(!MacOS27NativeBoundary.isImmediatelyBefore("boundary", "ice", in: ["hidden", "ice", "visible"]),
              "a missing boundary cannot be accepted")
        let display = CGRect(x: 0, y: 0, width: 1728, height: 1117)
        check(MacOS27NativeBoundary.canDrag(from: frame(270), to: ice, on: display),
              "two real menu bar endpoints can be dragged")
        check(!MacOS27NativeBoundary.canDrag(from: frame(7, y: 1121), to: ice, on: display),
              "a concealed off-display item cannot receive a synthetic drag")
        check(!MacOS27NativeBoundary.canDrag(from: frame(7, y: 1121), to: frame(37, y: 1121), on: display),
              "two retained overflow frames cannot be mistaken for a native row")
        check(!MacOS27NativeBoundary.canDrag(from: frame(270), to: ice, on: CGRect(x: -1728, y: 0, width: 1728, height: 1117)),
              "drag endpoints must belong to the same display")
        let handle = frame(291, width: 3)
        check(MacOS27NativeBoundary.canCheckImmediateHide(boundary: handle, control: ice, display: display),
              "a narrow native pair can enter live hit-test validation")
        check(!MacOS27NativeBoundary.canCheckImmediateHide(boundary: frame(280, width: 3), control: ice, display: display),
              "a wider gap requires complete ordering verification")
        check(!MacOS27NativeBoundary.canCheckImmediateHide(boundary: frame(303, width: 3), control: ice, display: display),
              "a boundary to the right cannot use immediate hiding")
        check(!MacOS27NativeBoundary.canCheckImmediateHide(boundary: frame(298, width: 3), control: ice, display: display),
              "overlapping transitional frames cannot use immediate hiding")
        check(!MacOS27NativeBoundary.canCheckImmediateHide(boundary: frame(280, width: 14), control: ice, display: display),
              "an already widened item cannot masquerade as a narrow handle")
        check(!MacOS27NativeBoundary.canCheckImmediateHide(boundary: frame(291, y: 6, width: 3), control: ice, display: display),
              "vertically unsettled frames require complete verification")
        check(!MacOS27NativeBoundary.canCheckImmediateHide(boundary: frame(291, y: 1121, width: 3), control: ice, display: display),
              "retained overflow geometry cannot enter the quick path")
        check(!MacOS27NativeBoundary.canCheckImmediateHide(boundary: CGRect(x: CGFloat.nan, y: 4, width: 3, height: 24), control: ice, display: display),
              "non-finite geometry cannot enter the quick path")
        print("\(assertions) native-boundary assertions passed")
    }
}
