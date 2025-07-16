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

// MARK: - Menu Bar Item Predicates

extension Predicates where Input == MenuBarItem {
    /// A group of predicates that separates menu bar items into sections.
    typealias SectionPredicates = (
        isInVisibleSection: NonThrowingPredicate,
        isInHiddenSection: NonThrowingPredicate,
        isInAlwaysHiddenSection: NonThrowingPredicate
    )

    private static func bounds(for item: MenuBarItem) -> CGRect {
        Bridging.getWindowBounds(for: item.windowID) ?? item.bounds
    }

    /// Creates a predicate that returns whether a menu bar item is in the visible section
    /// using the control item for the hidden section as a delimiter.
    static func isInVisibleSection(hiddenControlItem: MenuBarItem) -> NonThrowingPredicate {
        predicate { item in
            bounds(for: item).minX >= bounds(for: hiddenControlItem).maxX
        }
    }

    /// Creates a predicate that returns whether a menu bar item is in the hidden section
    /// using the control items for the hidden and always hidden sections as delimiters.
    static func isInHiddenSection(hiddenControlItem: MenuBarItem, alwaysHiddenControlItem: MenuBarItem?) -> NonThrowingPredicate {
        if let alwaysHiddenControlItem {
            predicate { item in
                bounds(for: item).maxX <= bounds(for: hiddenControlItem).minX &&
                bounds(for: item).minX >= bounds(for: alwaysHiddenControlItem).maxX
            }
        } else {
            predicate { item in
                bounds(for: item).maxX <= bounds(for: hiddenControlItem).minX
            }
        }
    }

    /// Creates a predicate that returns whether a menu bar item is in the always-hidden
    /// section using the control item for the always hidden section as a delimiter.
    static func isInAlwaysHiddenSection(alwaysHiddenControlItem: MenuBarItem?) -> NonThrowingPredicate {
        if let alwaysHiddenControlItem {
            predicate { item in
                bounds(for: item).maxX <= bounds(for: alwaysHiddenControlItem).minX
            }
        } else {
            predicate { false }
        }
    }

    /// Creates a group of predicates that separates menu bar items into sections.
    static func sectionPredicates(hiddenControlItem: MenuBarItem, alwaysHiddenControlItem: MenuBarItem?) -> SectionPredicates {
        SectionPredicates(
            isInVisibleSection: isInVisibleSection(hiddenControlItem: hiddenControlItem),
            isInHiddenSection: isInHiddenSection(hiddenControlItem: hiddenControlItem, alwaysHiddenControlItem: alwaysHiddenControlItem),
            isInAlwaysHiddenSection: isInAlwaysHiddenSection(alwaysHiddenControlItem: alwaysHiddenControlItem)
        )
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
