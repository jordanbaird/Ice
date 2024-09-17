//
//  Injection.swift
//  Ice
//

/// Updates the given value in place using a closure.
///
/// Use this function to repeatedly update a value while ensuring it is only mutated once.
func update<Value>(_ value: inout Value, body: (inout Value) throws -> Void) rethrows {
    try body(&value)
}

/// Updates the given value in place using a closure.
///
/// Use this function to repeatedly update a value while ensuring it is only mutated once.
func update<Value>(_ value: inout Value, body: (inout Value) async throws -> Void) async rethrows {
    try await body(&value)
}

/// Updates a copy of the given value using a closure and returns the updated value.
@discardableResult
func with<Value>(_ value: Value, update: (inout Value) throws -> Void) rethrows -> Value {
    var copy = value
    try update(&copy)
    return copy
}

/// Updates a copy of the given value using a closure and returns the updated value.
@discardableResult
func with<Value>(_ value: Value, update: (inout Value) async throws -> Void) async rethrows -> Value {
    var copy = value
    try await update(&copy)
    return copy
}
