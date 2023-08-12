//
//  MenuBuilder.swift
//  Ice
//

import Cocoa

@resultBuilder
enum MenuBuilder { }

extension MenuBuilder {
    /// Passes the given menu component through unmodified.
    static func buildBlock<Component: MenuComponent>(_ component: Component) -> Component {
        return component
    }

    /// Combines multiple menu components into a single result.
    static func buildBlock(_ components: (any MenuComponent)...) -> some MenuComponent {
        struct CombinedComponents: MenuComponent {
            let components: [any MenuComponent]

            func apply(to menu: NSMenu) {
                for component in components {
                    component.apply(to: menu)
                }
            }
        }
        return CombinedComponents(components: components)
    }

    /// Produces the final menu from the combined result of the previous blocks.
    static func buildFinalResult<Component: MenuComponent>(_ component: Component) -> NSMenu {
        let menu = NSMenu()
        component.apply(to: menu)
        return menu
    }
}

private struct OptionalMenuComponent<Content: MenuComponent>: MenuComponent {
    let content: Content?

    func apply(to menu: NSMenu) {
        content?.apply(to: menu)
    }
}

extension MenuBuilder {
    static func buildOptional<Component: MenuComponent>(_ component: Component?) -> some MenuComponent {
        return OptionalMenuComponent(content: component)
    }
}


extension MenuBuilder {
    /// Passes the given menu item through unmodified.
    static func buildBlock<Item: MenuItem>(_ item: Item) -> Item {
        return item
    }

    /// Combines multiple menu items into a single result.
    static func buildBlock(_ items: (any MenuItem)...) -> some MenuItem {
        struct CombinedItems: MenuItem {
            let items: [any MenuItem]

            func add(to menu: NSMenu) {
                for item in items {
                    item.add(to: menu)
                }
            }
        }
        return CombinedItems(items: items)
    }

    /// Produces the final item from the combined result of the previous blocks.
    static func buildFinalResult<Item: MenuItem>(_ item: Item) -> Item {
        return item
    }
}

private struct OptionalMenuItem<Content: MenuItem>: MenuItem {
    let content: Content?

    func add(to menu: NSMenu) {
        content?.add(to: menu)
    }
}

extension MenuBuilder {
    static func buildOptional<Item: MenuItem>(_ item: Item?) -> some MenuItem {
        return OptionalMenuItem(content: item)
    }
}
