//
//  MenuBarItemService.swift
//  Shared
//

import CoreGraphics
import Foundation

enum MenuBarItemService {
    static let name = "com.jordanbaird.Ice.MenuBarItemService"
}

extension MenuBarItemService {
    /// A request for the source process identifier of the menu bar
    /// item window with the given window ID.
    ///
    /// Only the fields the service actually needs are sent, to keep
    /// the decode surface on the service side as small as possible.
    struct SourcePIDQuery: Codable {
        let windowID: CGWindowID
        let bounds: CGRect
    }

    enum Request: Codable {
        case start
        case sourcePID(SourcePIDQuery)
    }

    enum Response: Codable {
        case start
        case sourcePID(pid_t?)
    }
}
