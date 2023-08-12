//
//  MenuComponent.swift
//  Ice
//

import Cocoa

// MARK: - MenuComponent

/// A type that can be used as a component in a ``MenuBuilder``.
///
/// Menu components differ from menu items in the way that they interact
/// with their menus; while menu items are added directly to the menu and
/// become part of its contents, menu components are _applied_ to the menu
/// to produce an overall change in its state, but don't necessarily become
/// part of the menu themselves.
protocol MenuComponent {
    /// Applies the component to the given menu.
    func apply(to menu: NSMenu)
}

// MARK: - MenuComponents

/// A namespace for types that can be used as components in a ``MenuBuilder``.
enum MenuComponents { }

// MARK: Title
extension MenuComponents {
    /// A menu component that adds a title to the menu.
    struct Title: MenuComponent {
        private let string: String

        /// Creates a title component with the given string.
        init(_ string: String) {
            self.string = string
        }

        func apply(to menu: NSMenu) {
            menu.title = string
        }
    }
}

// MARK: ItemGroup
extension MenuComponents {
    /// A menu component that adds a group of menu items to the menu.
    struct ItemGroup<Content: MenuItem>: MenuComponent {
        /// Options that specify the placement of separators around
        /// an item group's content.
        struct SeparatorPlacement: OptionSet {
            let rawValue: UInt8

            /// Places a separator before the group's content.
            static var before:  SeparatorPlacement { SeparatorPlacement(rawValue: 1 << 0) }

            /// Places a separator after the group's content.
            static var after:   SeparatorPlacement { SeparatorPlacement(rawValue: 1 << 1) }
        }

        /// Options that specify the placement of separators around
        /// the item group's content.
        let separatorPlacement: SeparatorPlacement

        /// The item group's content.
        let content: Content

        /// Creates an item group with the given separator placement and content.
        init(separatorPlacement: SeparatorPlacement = [], @MenuBuilder content: () -> Content) {
            self.separatorPlacement = separatorPlacement
            self.content = content()
        }

        func apply(to menu: NSMenu) {
            if separatorPlacement.contains(.before) {
                MenuItems.Separator().add(to: menu)
            }

            content.add(to: menu)

            if separatorPlacement.contains(.after) {
                MenuItems.Separator().add(to: menu)
            }
        }
    }
}
