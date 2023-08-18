//
//  Injection.swift
//  Ice
//

/// Modifies the given value by injecting it into the body of a closure.
///
/// The value is passed to the closure as an `inout` parameter, enabling
/// it to be changed during the closure's execution. The modified value
/// is then returned as the result of this function.
func inject<T>(_ value: T, update: (inout T) throws -> Void) rethrows -> T {
    var copy = value
    try update(&copy)
    return copy
}
