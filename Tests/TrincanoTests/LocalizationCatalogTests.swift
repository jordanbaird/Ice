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
                let stringUnit: Unit?
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
        entry.localizations?["pt-BR"]?.stringUnit?.value
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
}
