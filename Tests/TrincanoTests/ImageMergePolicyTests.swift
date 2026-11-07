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

    @Test func lateCaptureOfAnItemThatLeftIsDropped() {
        let old = ["kept": Img(id: 1, isFallback: false)]
        let new = ["kept": Img(id: 2, isFallback: false), "left": Img(id: 3, isFallback: false)]
        let result = ImageMergePolicy.merge(old: old, new: new, isFallback: \.isFallback, keepingOnly: ["kept"])
        #expect(Set(result.keys) == ["kept"])
        #expect(result["kept"]?.id == 2)
    }

    @Test func emptyValidKeysWithNonEmptyNewYieldsNothing() {
        let new = ["a": Img(id: 1, isFallback: false)]
        #expect(ImageMergePolicy.merge(old: [:], new: new, isFallback: \.isFallback, keepingOnly: []).isEmpty)
    }

    @Test func supersededRefreshIsDiscardedAndTheCurrentImageSurvives() {
        var sequencer = RefreshSequencer()
        let first = sequencer.begin()      // slow refresh A starts
        let second = sequencer.begin()     // refresh B starts later
        var images = [String: Img]()
        // B publishes first.
        if sequencer.isCurrent(second) {
            images = ImageMergePolicy.merge(
                old: images, new: ["a": Img(id: 2, isFallback: false)],
                isFallback: \.isFallback, keepingOnly: ["a"]
            )
        }
        // A arrives late with an older image: discarded.
        if sequencer.isCurrent(first) {
            images = ImageMergePolicy.merge(
                old: images, new: ["a": Img(id: 1, isFallback: false)],
                isFallback: \.isFallback, keepingOnly: ["a"]
            )
        }
        #expect(images["a"]?.id == 2)
        #expect(sequencer.isCurrent(first) == false)
    }
}
