//
//  Service.swift
//  MenuBarItemService
//

import Foundation

@main
enum Service {
    static func main() throws {
        Bridging.setProcessUnresponsiveTimeout(3)
        try Listener.shared.activate()
        RunLoop.current.run()
    }
}
