//
//  LocalizationCatalogTests.swift
//  TrincanoTests
//

import Foundation
import Testing

/// Checks the String Catalog (`Ice/Resources/Localizable.xcstrings`): English is
/// the source language and pt-BR must be complete and consistent.
struct LocalizationCatalogTests {
    private struct Catalog: Decodable {
        struct Entry: Decodable {
            struct Localization: Decodable {
                struct Unit: Decodable { let value: String }
                struct Plural: Decodable { let one: Variation?; let other: Variation? }
                struct Variation: Decodable { let stringUnit: Unit }
                struct Variations: Decodable { let plural: Plural? }
                let stringUnit: Unit?
                let variations: Variations?
            }
            let localizations: [String: Localization]?
        }
        let sourceLanguage: String
        let strings: [String: Entry]
    }

    private func loadCatalog() throws -> Catalog {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Ice/Resources/Localizable.xcstrings")
        return try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: url))
    }

    private func portuguese(_ entry: Catalog.Entry) -> String? {
        let localization = entry.localizations?["pt-BR"]
        return localization?.stringUnit?.value
            ?? localization?.variations?.plural?.other?.stringUnit.value
    }

    private func placeholders(in string: String) -> [String] {
        let pattern = try? NSRegularExpression(pattern: "%(?:\\d+\\$)?[@dfsl]+")
        let range = NSRange(string.startIndex..., in: string)
        return (pattern?.matches(in: string, range: range) ?? []).compactMap {
            Range($0.range, in: string).map { String(string[$0]) }
        }
    }

    @Test func englishIsTheSourceLanguage() throws {
        #expect(try loadCatalog().sourceLanguage == "en")
    }

    @Test func everyKeyHasANonEmptyPortugueseTranslation() throws {
        let catalog = try loadCatalog()
        #expect(catalog.strings.count > 100)
        for (key, entry) in catalog.strings {
            let value = portuguese(entry)
            #expect(value?.isEmpty == false, "pt-BR missing for: \(key)")
        }
    }

    @Test func placeholdersMatchBetweenEnglishAndPortuguese() throws {
        for (key, entry) in try loadCatalog().strings {
            guard let value = portuguese(entry) else { continue }
            #expect(placeholders(in: key) == placeholders(in: value), "placeholder mismatch: \(key)")
        }
    }

    @Test func theBarIsCalledBarraDoTrincanoInPortuguese() throws {
        for (key, entry) in try loadCatalog().strings where key.contains("Trincano Bar") {
            let value = portuguese(entry) ?? ""
            #expect(value.contains("Barra do Trincano"), "\(key) -> \(value)")
            #expect(!value.contains("Trincano Bar"), "English product term left in: \(key)")
        }
    }

    @Test func productNameIsNeverTranslated() throws {
        for (key, entry) in try loadCatalog().strings where key.contains("Trincano") {
            #expect((portuguese(entry) ?? "").contains("Trincano"), "name lost in: \(key)")
        }
    }

    /// The sidebar is 220 pt wide at the default row size; the worst case is
    /// pt-BR. Titles must stay short enough to fit on one line with the icon.
    @Test func sidebarTitlesFitTheSidebarInPortuguese() throws {
        let catalog = try loadCatalog()
        let sidebarKeys = [
            "General", "Menu Bar Layout", "Menu Bar Appearance",
            "Hotkeys", "Advanced", "About",
        ]
        for key in sidebarKeys {
            let value = try #require(catalog.strings[key].flatMap(portuguese), "missing: \(key)")
            #expect(value.count <= 16, "sidebar title too long for 220 pt: \(key) -> \(value)")
        }
    }
}
