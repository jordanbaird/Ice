//
//  KeyCommand.Name+toggle.swift
//  Ice
//

import SwiftKeys

extension KeyCommand.Name {
    static func toggle(section: StatusBarSection) -> Self {
        Self("Hotkey-Toggle-Section-\(section.uuid)")
    }
}
