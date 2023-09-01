//
//  KeyCommand.Name+toggle.swift
//  Ice
//

import SwiftKeys

extension KeyCommand.Name {
    static func toggleSection(withName name: StatusBarSection.Name) -> Self {
        Self("Hotkey-Toggle-Section-\(name.rawValue.filter { !$0.isWhitespace })")
    }
}
