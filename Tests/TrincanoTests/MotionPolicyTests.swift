//
//  MotionPolicyTests.swift
//  TrincanoTests
//

import Testing

struct MotionPolicyTests {
    @Test func reduceMotionDisablesTheTransition() {
        for base in [0.1, 0.2, 0.35, 1.0] {
            #expect(MotionPolicy.duration(base: base, reduceMotion: true) == 0)
        }
    }

    @Test func durationsAreClampedToTheDesignRange() {
        #expect(MotionPolicy.duration(base: 0.05, reduceMotion: false) == MotionPolicy.minimum)
        #expect(MotionPolicy.duration(base: 0.5, reduceMotion: false) == MotionPolicy.maximum)
        #expect(MotionPolicy.duration(base: 0.2, reduceMotion: false) == 0.2)
    }

    @Test func rangeIs150To300Milliseconds() {
        #expect(MotionPolicy.minimum == 0.15)
        #expect(MotionPolicy.maximum == 0.30)
    }

    @Test func standardDurationsStayInsideTheRange() {
        for kind in MotionPolicy.Kind.allCases {
            let d = MotionPolicy.duration(for: kind, reduceMotion: false)
            #expect(d >= MotionPolicy.minimum && d <= MotionPolicy.maximum, "\(kind)")
            #expect(MotionPolicy.duration(for: kind, reduceMotion: true) == 0)
        }
    }
}
