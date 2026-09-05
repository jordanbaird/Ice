// clang -c Tests/SpaceTypeBridgeFixture.c -o <fixture.o>
// swiftc -parse-as-library Shared/Bridging/Shims.swift \
//   Tests/SpaceTypeBridgeTests.swift <fixture.o> -o <tests>
// The fixture performs no actual WindowServer or application operations.
import Foundation

@main
private struct SpaceTypeBridgeTests {
    static func main() {
        var failures = 0
        func check(_ condition: Bool, _ label: String) {
            print("\(condition ? "PASS" : "FAIL"): \(label)")
            if !condition { failures += 1 }
        }
        // This explicit signature is a regression check: declaring the C
        // result as a Swift enum will fail compilation, not silently use its
        // compact case tag (fullscreen tag 2 versus native raw value 4).
        let readType: (CGSConnectionID, CGSSpaceID) -> UInt32 = CGSSpaceGetType
        for value: UInt32 in [0, 1, 2, 3, 4, 5, .max] {
            let type = readType(0, Int(value))
            check(type == value, "native raw type \(value) is preserved")
            check((type == CGSSpaceType.fullscreen.rawValue) == (value == 4),
                  "only native type 4 is fullscreen (received \(value))")
        }
        exit(failures == 0 ? 0 : 1)
    }
}
