//
//  KeyCommand.Name+toggle.swift
//  Ice
//

import SwiftKeys

extension KeyCommand.Name {
    static func toggle(_ section: StatusBar.Section) -> Self {
        Self("Hotkey-Toggle-Section-\(section.rawValue)")
    }
}
