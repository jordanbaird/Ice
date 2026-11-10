import Testing
@testable import IceMacOS27Core

/// Simulates MenuBarAgent: an item shows if any live assertion allows it.
@MainActor
final class FakeConcealmentBackend: ConcealmentBackend27 {
    final class Token: ConcealmentToken27 {
        let allowed: Set<String>
        init(allowed: Set<String>) { self.allowed = allowed }
    }

    struct Rejected: Error {}

    var universe: Set<String>
    var rejectNextActivation = false
    private(set) var liveTokens = [Token]()
    private(set) var activationCount = 0
    /// What the bar conceals after every activation and invalidation.
    private(set) var history = [Set<String>]()

    init(universe: Set<String>) {
        self.universe = universe
    }

    var concealed: Set<String> {
        guard !liveTokens.isEmpty else { return [] }
        let allowed = liveTokens.reduce(into: Set<String>()) { $0.formUnion($1.allowed) }
        return universe.subtracting(allowed)
    }

    func activate(allowedBundleIDs: [String]) async throws -> ConcealmentToken27 {
        if rejectNextActivation {
            rejectNextActivation = false
            throw Rejected()
        }
        activationCount += 1
        let token = Token(allowed: Set(allowedBundleIDs))
        liveTokens.append(token)
        history.append(concealed)
        return token
    }

    func invalidate(_ token: ConcealmentToken27) {
        liveTokens.removeAll { $0 === token }
        history.append(concealed)
    }
}

@Suite("ConcealmentController27")
@MainActor
struct ConcealmentController27Tests {
    let running: Set<String> = ["visible.app", "hidden.app", "always.app"]
    let allHidden: [Set<String>] = [["hidden.app", "always.app"]]
    let hiddenRevealed: [Set<String>] = [["always.app"]]

    @Test("Hiding conceals the target set")
    func hiding() async throws {
        let backend = FakeConcealmentBackend(universe: running)
        let controller = ConcealmentController27(backend: backend)
        try await controller.apply(target: allHidden, running: running)
        #expect(backend.concealed == ["hidden.app", "always.app"])
        #expect(controller.isActive)
    }

    @Test("Revealing the hidden section never exposes always-hidden apps")
    func revealing() async throws {
        let backend = FakeConcealmentBackend(universe: running)
        let controller = ConcealmentController27(backend: backend)
        try await controller.apply(target: allHidden, running: running)
        try await controller.apply(target: hiddenRevealed, running: running)
        #expect(backend.concealed == ["always.app"])
        #expect(backend.history.allSatisfy { $0.contains("always.app") })
    }

    @Test("Hiding again never exposes always-hidden apps")
    func hidingAgain() async throws {
        let backend = FakeConcealmentBackend(universe: running)
        let controller = ConcealmentController27(backend: backend)
        try await controller.apply(target: allHidden, running: running)
        try await controller.apply(target: hiddenRevealed, running: running)
        try await controller.apply(target: allHidden, running: running)
        #expect(backend.concealed == ["hidden.app", "always.app"])
        #expect(backend.history.allSatisfy { $0.contains("always.app") })
    }

    @Test("Re-applying the same state does not churn assertions")
    func noChurn() async throws {
        let backend = FakeConcealmentBackend(universe: running)
        let controller = ConcealmentController27(backend: backend)
        try await controller.apply(target: allHidden, running: running)
        try await controller.apply(target: allHidden, running: running)
        #expect(backend.activationCount == 1)
    }

    @Test("A launched app is allowed without exposing concealed apps")
    func launchedApp() async throws {
        let backend = FakeConcealmentBackend(universe: running.union(["new.app"]))
        let controller = ConcealmentController27(backend: backend)
        try await controller.apply(target: allHidden, running: running)
        #expect(backend.concealed.contains("new.app"))
        try await controller.apply(target: allHidden, running: running.union(["new.app"]))
        #expect(backend.concealed == ["hidden.app", "always.app"])
        #expect(backend.history.allSatisfy { $0.isSuperset(of: ["hidden.app", "always.app"]) })
    }

    @Test("A rejected activation keeps the previous state")
    func rejected() async throws {
        let backend = FakeConcealmentBackend(universe: running)
        let controller = ConcealmentController27(backend: backend)
        try await controller.apply(target: allHidden, running: running)
        backend.rejectNextActivation = true
        await #expect(throws: FakeConcealmentBackend.Rejected.self) {
            try await controller.apply(target: hiddenRevealed, running: running)
        }
        #expect(backend.concealed == ["hidden.app", "always.app"])
        #expect(backend.liveTokens.count == 1)
    }

    @Test("Releasing restores every item")
    func releasing() async throws {
        let backend = FakeConcealmentBackend(universe: running)
        let controller = ConcealmentController27(backend: backend)
        try await controller.apply(target: allHidden, running: running)
        controller.releaseAll()
        #expect(backend.concealed.isEmpty)
        #expect(!controller.isActive)
    }
}
