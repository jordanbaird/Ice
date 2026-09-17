import CoreGraphics
import Foundation

@main
struct AverageColorTests {
    static func image(red: CGFloat = 1, alpha: CGFloat) -> CGImage {
        let context = CGContext(data: nil, width: 10, height: 10, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(red: red, green: 0, blue: 0, alpha: alpha)
        context.fill(CGRect(x: 0, y: 0, width: 10, height: 10))
        return context.makeImage()!
    }

    static func main() {
        var failed = 0
        func check(_ condition: Bool, _ message: String) {
            print("\(condition ? "PASS" : "FAIL"): \(message)")
            if !condition { failed += 1 }
        }
        let transparent = image(alpha: 0)
        check(transparent.averageColor() == nil, "all-transparent image has no average")
        check(transparent.averageColor(option: .ignoreAlpha) == nil, "ignoreAlpha does not bypass empty-pixel protection")
        check(image(alpha: 0.25).averageColor() == nil, "all pixels below threshold have no average")
        let opaque = image(alpha: 1).averageColor()!
        check(opaque.components!.allSatisfy(\.isFinite), "ordinary averages contain only finite components")
        check(abs(opaque.components![0] - 1) < 0.01 && opaque.alpha == 1, "opaque red retains its color and alpha")
        check(transparent.averageColor(alphaThreshold: 0)?.components?.allSatisfy(\.isFinite) == true,
              "an explicit zero threshold includes transparent pixels without division by zero")
        check(image(alpha: 0.75).averageColor()?.alpha ?? 0 > 0.7, "partly transparent qualifying pixels remain supported")
        if !CommandLine.arguments.contains("--baseline") {
            check(opaque.alpha.isFinite && transparent.averageColor(alphaThreshold: .nan) == nil,
                  "invalid threshold does not trap during integer conversion")
            check(transparent.averageColor(alphaThreshold: .infinity) == nil, "infinite threshold is rejected")
        }
        exit(failed == 0 ? 0 : 1)
    }
}
