//
//  ImageMergePolicyTests.swift
//  TrincanoTests
//

import Testing

struct ImageMergePolicyTests {
    private struct Img: Equatable {
        let id: Int
        let isFallback: Bool
    }

    @Test func realCaptureReplacesFallback() {
        let old = ["a": Img(id: 1, isFallback: true)]
        let new = ["a": Img(id: 2, isFallback: false)]
        let result = ImageMergePolicy.merge(old: old, new: new, isFallback: \.isFallback)
        #expect(result["a"]?.id == 2)
    }

    @Test func fallbackNeverReplacesRealCapture() {
        let old = ["a": Img(id: 1, isFallback: false)]
        let new = ["a": Img(id: 2, isFallback: true)]
        let result = ImageMergePolicy.merge(old: old, new: new, isFallback: \.isFallback)
        #expect(result["a"]?.id == 1)
    }

    @Test func fallbackIsUsedWhenNothingCapturedBefore() {
        let new = ["a": Img(id: 2, isFallback: true)]
        let result = ImageMergePolicy.merge(old: [:], new: new, isFallback: \.isFallback)
        #expect(result["a"]?.id == 2)
    }

    @Test func fallbackReplacesOlderFallbackAndKeepsUnrelatedKeys() {
        let old = ["a": Img(id: 1, isFallback: true), "b": Img(id: 9, isFallback: false)]
        let new = ["a": Img(id: 2, isFallback: true)]
        let result = ImageMergePolicy.merge(old: old, new: new, isFallback: \.isFallback)
        #expect(result["a"]?.id == 2)
        #expect(result["b"]?.id == 9)
    }

    @Test func staleKeysAreEvicted() {
        let old = ["gone": Img(id: 1, isFallback: false), "kept": Img(id: 2, isFallback: false)]
        let new = ["new": Img(id: 3, isFallback: false)]
        let result = ImageMergePolicy.merge(
            old: old, new: new, isFallback: \.isFallback, keepingOnly: ["kept", "new"]
        )
        #expect(Set(result.keys) == ["kept", "new"])
    }

    @Test func evictionStillProtectsRealCapturesFromFallbacks() {
        let old = ["a": Img(id: 1, isFallback: false)]
        let new = ["a": Img(id: 2, isFallback: true)]
        let result = ImageMergePolicy.merge(old: old, new: new, isFallback: \.isFallback, keepingOnly: ["a"])
        #expect(result["a"]?.id == 1)
    }

    @Test func noValidKeysEvictsEverythingOld() {
        let old = ["a": Img(id: 1, isFallback: false)]
        let result = ImageMergePolicy.merge(old: old, new: [:], isFallback: \.isFallback, keepingOnly: [])
        #expect(result.isEmpty)
    }
}
