//
//  LocalizationUtils.swift
//  Ice
//

import Foundation

enum LocalizationUtils {
    static func localizedString(_ key: String, language: Language) -> String {
        let table: [String: String]
        switch language {
        case .english:
            table = LocalizationData.en
        case .chinese:
            table = LocalizationData.zhHans
        }
        return table[key] ?? key
    }
}

extension String {
    func localized(for language: Language) -> String {
        LocalizationUtils.localizedString(self, language: language)
    }
}
