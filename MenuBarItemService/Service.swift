//
//  Service.swift
//  MenuBarItemService
//

import Foundation

@main
enum Service {
    static func main() throws {
        try Listener.shared.activate()
        RunLoop.current.run()
    }
}
