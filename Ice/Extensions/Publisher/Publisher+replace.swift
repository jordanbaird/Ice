//
//  Publisher+replace.swift
//  Ice
//

import Combine

extension Publisher {
    /// Replaces the output of this publisher with a new value.
    func replace<Value>(with value: Value) -> some Publisher<Value, Failure> {
        map { _ in value }
    }
}
