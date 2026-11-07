//
//  Signposts.swift
//  Shared
//

import OSLog

/// Performance signposts for the hot paths (open/close sections, Trincano
/// Bar, layout, search, mouse handling).
///
/// Read them with `log show --signpost --predicate 'subsystem == "<bundle id>"'`
/// or in Instruments (os_signpost / Points of Interest). See
/// `scripts/measure-signposts.sh`.
enum Signposts {
    static let signposter = OSSignposter(
        subsystem: Bundle.main.bundleIdentifier ?? "",
        category: "Performance"
    )

    /// Measures a synchronous operation.
    @discardableResult
    static func measure<T>(_ name: StaticString, _ body: () throws -> T) rethrows -> T {
        let state = signposter.beginInterval(name, id: signposter.makeSignpostID())
        defer { signposter.endInterval(name, state) }
        return try body()
    }

    /// Measures an asynchronous operation.
    @discardableResult
    static func measure<T>(
        _ name: StaticString,
        isolation: isolated (any Actor)? = #isolation,
        _ body: () async throws -> T
    ) async rethrows -> T {
        let state = signposter.beginInterval(name, id: signposter.makeSignpostID())
        defer { signposter.endInterval(name, state) }
        return try await body()
    }

    /// Marks a single event.
    static func event(_ name: StaticString) {
        signposter.emitEvent(name)
    }
}
