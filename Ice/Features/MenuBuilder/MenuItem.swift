//
//  MenuItem.swift
//  Ice
//

import Cocoa
import SwiftKeys

// MARK: - MenuItem

/// A type that can be used as a menu item in a ``MenuBuilder``.
///
/// Menu items differ from menu components in the way that they interact
/// with their menus; while menu components are applied to the menu to
/// produce an overall change in its state, menu items are added directly
/// to the menu and become part of its contents.
protocol MenuItem {
    /// Adds the menu item to the given menu.
    func add(to menu: NSMenu)
}

// MARK: - MenuItems

/// A namespace for types that can be used as menu items in a ``MenuBuilder``.
enum MenuItems { }

// MARK: Separator
extension MenuItems {
    /// A menu item used to separate logical groups of menu commands.
    struct Separator: MenuItem {
        func add(to menu: NSMenu) {
            menu.addItem(.separator())
        }
    }
}

// MARK: Item
extension MenuItems {
    /// A standard menu item with a title, key equivalent, modifier mask, and action.
    struct Item: MenuItem {
        typealias Modifiers = NSEvent.ModifierFlags

        private enum ActionWrapper {
            case closure((NSMenuItem) -> Void)
            case selector(Selector)
        }

        private class AppKitMenuItem: NSMenuItem {
            private let closure: ((NSMenuItem) -> Void)?

            init(title: String, wrapper: ActionWrapper, keyEquivalent: String, modifierMask: Modifiers) {
                switch wrapper {
                case .closure(let closure):
                    self.closure = closure
                    super.init(title: title, action: #selector(performAction), keyEquivalent: keyEquivalent)
                    self.target = self
                case .selector(let selector):
                    self.closure = nil
                    super.init(title: title, action: selector, keyEquivalent: keyEquivalent)
                }
                self.keyEquivalentModifierMask = modifierMask
            }

            @available(*, unavailable)
            required init(coder: NSCoder) {
                fatalError("init(coder:) has not been implemented")
            }

            @objc private func performAction(_ sender: NSMenuItem) {
                closure?(sender)
            }
        }

        private let base: AppKitMenuItem

        private init(
            title: String,
            keyEquivalent: String,
            modifierMask: Modifiers,
            wrapper: ActionWrapper
        ) {
            self.base = AppKitMenuItem(
                title: title,
                wrapper: wrapper,
                keyEquivalent: keyEquivalent,
                modifierMask: modifierMask
            )
        }

        /// Creates a menu item with the given title, key equivalent, modifier mask,
        /// and action.
        ///
        /// - Parameters:
        ///   - title: The menu item's title.
        ///   - keyEquivalent: The menu item's unmodified key equivalent.
        ///   - modifierMask: The modifier mask to apply to the menu item's key equivalent.
        ///   - closure: A closure that is performed as the menu item's action.
        init(
            title: String,
            key keyEquivalent: String = "",
            modifiers modifierMask: Modifiers = [],
            action closure: @escaping (NSMenuItem) -> Void
        ) {
            self.init(
                title: title,
                keyEquivalent: keyEquivalent,
                modifierMask: modifierMask,
                wrapper: .closure(closure)
            )
        }

        /// Creates a menu item with the given title, key equivalent, modifier mask,
        /// and action.
        ///
        /// - Parameters:
        ///   - title: The menu item's title.
        ///   - keyEquivalent: The menu item's unmodified key equivalent.
        ///   - modifierMask: The modifier mask to apply to the menu item's key equivalent.
        ///   - closure: A closure that is performed as the menu item's action.
        init(
            title: String,
            key keyEquivalent: String = "",
            modifiers modifierMask: Modifiers = [],
            action closure: @escaping () -> Void
        ) {
            self.init(
                title: title,
                key: keyEquivalent,
                modifiers: modifierMask,
                action: { _ in closure() }
            )
        }

        /// Creates a menu item with the given title, key equivalent, modifier mask,
        /// and action.
        ///
        /// - Parameters:
        ///   - title: The menu item's title.
        ///   - keyEquivalent: The menu item's unmodified key equivalent.
        ///   - modifierMask: The modifier mask to apply to the menu item's key equivalent.
        ///   - selector: A selector that is performed as the menu item's action.
        init(
            title: String,
            key keyEquivalent: String = "",
            modifiers modifierMask: Modifiers = [],
            action selector: Selector
        ) {
            self.init(
                title: title,
                keyEquivalent: keyEquivalent,
                modifierMask: modifierMask,
                wrapper: .selector(selector)
            )
        }

        func add(to menu: NSMenu) {
            menu.addItem(base)
        }

        func keyCommand(name: KeyCommand.Name) -> Self {
            base.keyCommand = KeyCommand(name: name)
            return self
        }
    }
}
