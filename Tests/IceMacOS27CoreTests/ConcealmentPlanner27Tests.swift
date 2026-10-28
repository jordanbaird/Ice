import Testing
@testable import IceMacOS27Core

@Suite("ConcealmentPlanner27")
struct ConcealmentPlanner27Tests {
    let layout: [String: MacOS27Section] = ["visible.app": .visible, "hidden.app": .hidden, "always.app": .alwaysHidden]

    @Test("Everything hidden conceals hidden and always-hidden apps")
    func allHidden() {
        #expect(ConcealmentPlanner27.concealedSets(layout: layout, state: .allHidden) == [["hidden.app", "always.app"]])
    }

    @Test("Revealing the hidden section conceals only always-hidden apps")
    func hiddenRevealed() {
        #expect(ConcealmentPlanner27.concealedSets(layout: layout, state: .hiddenRevealed) == [["always.app"]])
    }

    @Test("Revealing everything needs no assertion")
    func allRevealed() {
        #expect(ConcealmentPlanner27.concealedSets(layout: layout, state: .allRevealed).isEmpty)
    }

    @Test("Nothing to conceal needs no assertion")
    func nothingToConceal() {
        #expect(ConcealmentPlanner27.concealedSets(layout: ["a": .visible], state: .allHidden).isEmpty)
        #expect(ConcealmentPlanner27.concealedSets(layout: ["a": .hidden], state: .hiddenRevealed).isEmpty)
    }

    @Test("The allowlist is every running app except the concealed ones, sorted")
    func allowlist() {
        #expect(ConcealmentPlanner27.allowlist(concealing: ["b"], running: ["z", "a", "b"]) == ["a", "z"])
    }

    @Test("Live assertions conceal only what all of them conceal")
    func effectivelyConcealed() {
        #expect(ConcealmentPlanner27.effectivelyConcealed(sets: [["b", "c"], ["c"]]) == ["c"])
        #expect(ConcealmentPlanner27.effectivelyConcealed(sets: []).isEmpty)
    }
}
