//
//  NativeDragVisibilityStateTests.swift
//  Ice
//

// Compile together with Ice/MenuBar/MenuBarItems/MacOS27NativeBoundary.swift.
// Pure state-sequence checks; no native events, status items or permissions.
@main
enum NativeDragVisibilityStateTests {
    static func main() {
        var assertions = 0
        func check(_ condition: Bool, _ description: String) {
            precondition(condition, description)
            assertions += 1
            print("PASS: \(description)")
        }

        var state = MacOS27NativeDragVisibilityState()
        check(state.shouldApplyVisibilityUpdate(), "idle toggles apply immediately")
        state.beginDrag()
        check(!state.endDrag(), "an unchanged drag does not trigger another visibility update")

        state.beginDrag()
        check(!state.shouldApplyVisibilityUpdate(), "expand cannot withdraw a held drag source")
        check(!state.shouldApplyVisibilityUpdate(), "a newer hide is coalesced while inputs are held")
        check(state.endDrag(), "input release requests one sync of current intent")
        check(state.shouldApplyVisibilityUpdate(), "the final hide can apply after release")
        check(!state.endDrag(), "balanced cleanup cannot replay an old pending update")

        state.beginDrag()
        check(!state.shouldApplyVisibilityUpdate(), "Layout entry cannot replace a held boundary")
        check(!state.shouldApplyVisibilityUpdate(), "Layout closure still waits for input release")
        check(state.endDrag(), "release resyncs the latest Layout state only")

        state.beginDrag()
        check(!state.shouldApplyVisibilityUpdate(), "cancellation before mouse-down retains pending intent")
        check(state.endDrag(), "throw cleanup releases the pin and applies current intent")
        state.beginDrag()
        check(!state.endDrag(), "retry does not inherit the cancelled attempt's pending update")

        state.beginDrag()
        state.beginDrag()
        check(!state.shouldApplyVisibilityUpdate(), "nested holds also defer visibility")
        check(!state.endDrag(), "one release cannot unpin another active hold")
        check(!state.shouldApplyVisibilityUpdate(), "the remaining hold protects native scenes")
        check(state.endDrag(), "the last release emits the single pending sync")
        check(state.shouldApplyVisibilityUpdate(), "no pin remains after complete cleanup")

        // Model the manager's callback contract: it rereads state when unpinned
        // instead of retaining a closure with the first toggle's old value.
        var currentIntent = "hidden"
        var appliedIntents = [String]()
        state.beginDrag()
        for intent in ["expanded", "layout-open", "layout-closed", "hidden"] {
            currentIntent = intent
            if state.shouldApplyVisibilityUpdate() { appliedIntents.append(currentIntent) }
        }
        check(appliedIntents.isEmpty, "no intermediate toggle or Layout intent mutates a held scene")
        if state.endDrag(), state.shouldApplyVisibilityUpdate() {
            appliedIntents.append(currentIntent)
        }
        check(appliedIntents == ["hidden"], "release applies the newest intent exactly once")

        print("\(assertions) native-drag visibility assertions passed")
    }
}
