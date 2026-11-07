//
//  MenuBarItemService.swift
//  Shared
//

import Foundation

enum MenuBarItemService {
    static let name = "br.com.pilutech.trincano.MenuBarItemService"

    /// The signing identifier (bundle identifier) of the app that hosts the service.
    static let appSigningIdentifier = "br.com.pilutech.trincano"
}

extension MenuBarItemService {
    enum Request: Codable {
        case start
        case sourcePID(WindowInfo)
    }

    enum Response: Codable {
        case start
        case sourcePID(pid_t?)
    }
}
