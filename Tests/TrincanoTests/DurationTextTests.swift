//
//  DurationTextTests.swift
//  TrincanoTests
//

import Foundation
import Testing

struct DurationTextTests {
    private let english = Locale(identifier: "en_US")
    private let portuguese = Locale(identifier: "pt_BR")

    @Test func englishPluralsAndFractions() {
        #expect(DurationText.string(seconds: 0, locale: english) == "0 seconds")
        #expect(DurationText.string(seconds: 1, locale: english) == "1 second")
        #expect(DurationText.string(seconds: 2, locale: english) == "2 seconds")
        #expect(DurationText.string(seconds: 0.1, locale: english) == "0.1 seconds")
    }

    @Test func portuguesePluralsAndDecimalComma() {
        #expect(DurationText.string(seconds: 0, locale: portuguese) == "0 segundo")      // CLDR: 0 is singular in pt
        #expect(DurationText.string(seconds: 1, locale: portuguese) == "1 segundo")
        #expect(DurationText.string(seconds: 2, locale: portuguese) == "2 segundos")
        #expect(DurationText.string(seconds: 0.1, locale: portuguese) == "0,1 segundo")
        #expect(DurationText.string(seconds: 15, locale: portuguese) == "15 segundos")
    }

    @Test func noEnglishWordsLeakIntoPortuguese() {
        for value in [0.0, 0.1, 0.5, 1, 2, 15, 60] {
            let text = DurationText.string(seconds: value, locale: portuguese)
            #expect(!text.contains("second ") && !text.hasSuffix("second") && !text.hasSuffix("seconds"), "\(text)")
        }
    }
}
