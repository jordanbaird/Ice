//
//  Predicates.swift
//  Ice
//

import Cocoa

/// A namespace for predicates.
enum Predicates<Input> {
    /// A throwing predicate that takes an input and returns a Boolean value.
    typealias ThrowingPredicate = (Input) throws -> Bool

    /// A predicate that takes an input and returns a Boolean value.
    typealias NonThrowingPredicate = (Input) -> Bool

    /// Creates a throwing predicate that takes an input and returns a Boolean value.
    static func predicate(_ body: @escaping (Input) throws -> Bool) -> ThrowingPredicate {
        return body
    }

    /// Creates a predicate takes an input and returns a Boolean value.
    static func predicate(_ body: @escaping (Input) -> Bool) -> NonThrowingPredicate {
        return body
    }

    /// Creates a throwing predicate that doesn't take an input and returns a Boolean value.
    static func predicate(_ body: @escaping () throws -> Bool) -> ThrowingPredicate {
        predicate { _ in try body() }
    }

    /// Creates a predicate that doesn't take an input and returns a Boolean value.
    static func predicate(_ body: @escaping () -> Bool) -> NonThrowingPredicate {
        predicate { _ in body() }
    }
}

// MARK: - Control Item Predicates

extension Predicates where Input == NSLayoutConstraint {
    static func controlItemConstraint(button: NSStatusBarButton) -> NonThrowingPredicate {
        predicate { constraint in
            constraint.secondItem === button.superview
        }
    }
}
