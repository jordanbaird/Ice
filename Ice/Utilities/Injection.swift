//
//  Injection.swift
//  Ice
//

/// Updates the given value using a closure.
///
/// Use this function to repeatedly update a value while ensuring it
/// is only mutated once.
///
/// - Example 1:
///
/// ```swift
/// var count = 0 {
///     didSet { print("Count: \(count)") }
/// }
///
/// for _ in 0..<1000 {
///     count += 1
/// }
///
/// // Prints:
/// // Count: 1
/// // Count: 2
/// // Count: 3
/// // ...
/// // ...
/// // Count: 1000
/// ```
///
/// - Example 2:
///
/// ```swift
/// var count = 0 {
///     didSet { print("Count: \(count)") }
/// }
///
/// update(&count) { count in
///     for _ in 0..<1000 {
///         count += 1
///     }
/// }
///
/// // Prints:
/// // Count: 1000
/// ```
func update<Value>(_ value: inout Value, body: (inout Value) throws -> Void) rethrows {
    try body(&value)
}

/// Updates the given value using a closure.
///
/// Use this function to repeatedly update a value while ensuring it
/// is only mutated once.
///
/// - Example 1:
///
/// ```swift
/// var count = 0 {
///     didSet { print("Count: \(count)") }
/// }
///
/// for _ in 0..<1000 {
///     count += 1
/// }
///
/// // Prints:
/// // Count: 1
/// // Count: 2
/// // Count: 3
/// // ...
/// // ...
/// // Count: 1000
/// ```
///
/// - Example 2:
///
/// ```swift
/// var count = 0 {
///     didSet { print("Count: \(count)") }
/// }
///
/// update(&count) { count in
///     for _ in 0..<1000 {
///         count += 1
///     }
/// }
///
/// // Prints:
/// // Count: 1000
/// ```
func update<Value>(_ value: inout Value, body: (inout Value) async throws -> Void) async rethrows {
    try await body(&value)
}

/// Updates a copy of the given value using a closure.
///
/// Use this function as shorthand for the following pattern:
///
/// * Example 1:
///
/// ```swift
/// let item = Item(index: 0, title: "Title")
///
/// let item2: Item = {
///     var copy = item
///     copy.index += 1
///     copy.title = "Title2"
///     return copy
/// }()
/// ```
///
/// * Example 2:
///
/// ```swift
/// let item = Item(index: 0, title: "Title")
///
/// let item2 = with(item) { item in
///     item.index += 1
///     item.title = "Title2"
/// }
/// ```
@discardableResult
func with<Value>(_ value: Value, update: (inout Value) throws -> Void) rethrows -> Value {
    var copy = value
    try update(&copy)
    return copy
}

/// Updates a copy of the given value using a closure.
///
/// Use this function as shorthand for the following pattern:
///
/// * Example 1:
///
/// ```swift
/// let item = Item(index: 0, title: "Title")
///
/// let item2: Item = {
///     var copy = item
///     copy.index += 1
///     copy.title = "Title2"
///     return copy
/// }()
/// ```
///
/// * Example 2:
///
/// ```swift
/// let item = Item(index: 0, title: "Title")
///
/// let item2 = with(item) { item in
///     item.index += 1
///     item.title = "Title2"
/// }
/// ```
@discardableResult
func with<Value>(_ value: Value, update: (inout Value) async throws -> Void) async rethrows -> Value {
    var copy = value
    try await update(&copy)
    return copy
}
