//
//  Helpers.swift
//  Ice
//

// MARK: - Update

/// Updates the given value in place using a closure.
///
/// Use this function to group multiple updates under one mutation.
func update<Value, E: Error>(
    _ value: inout Value,
    _ body: (inout Value) throws(E) -> Void
) throws(E) {
    try body(&value)
}

/// Updates the given value in place using a closure.
///
/// Use this function to group multiple updates under one mutation.
func update<Value, E: Error>(
    _ value: inout Value,
    _ body: (inout Value) async throws(E) -> Void
) async throws(E) {
    try await body(&value)
}

// MARK: - With Mutable Copy

/// Invokes the given closure with a mutable copy of the given value.
@discardableResult
func withMutableCopy<Value: Copyable, E: Error>(
    of value: Value,
    _ body: (inout Value) throws(E) -> Void
) throws(E) -> Value {
    var mutable = copy value
    try body(&mutable)
    return mutable
}
