//
//  KeyCommand.Name+toggle.swift
//  Ice
//

import SwiftKeys

extension KeyCommand.Name {
    static func toggle(_ section: StatusBar.Section) -> Self {
        Self(section.identifier, prefix: "ToggleSection", separator: "-")
    }
}
