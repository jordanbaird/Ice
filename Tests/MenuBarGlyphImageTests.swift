// Compile with the real MenuBarGlyphImage.swift; no app launch or capture needed.
import CoreGraphics
import Foundation
import ImageIO

@main
struct MenuBarGlyphImageTests {
    static func makeImage(background: CGFloat, colored: Bool = false, empty: Bool = false, strokeOnly: Bool = false) -> CGImage {
        let context = CGContext(data: nil, width: 48, height: 48, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(gray: background, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 48, height: 48))
        if !empty {
            if colored {
                context.setFillColor(red: 1, green: 0.05, blue: 0.1, alpha: 1)
            } else {
                context.setFillColor(CGColor(gray: background < 0.5 ? 1 : 0, alpha: 1))
            }
            if !strokeOnly { context.fillEllipse(in: CGRect(x: 12, y: 12, width: 24, height: 24)) }
            context.fill(CGRect(x: 4, y: 4, width: 1, height: 12))
        }
        return context.makeImage()!
    }

    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        precondition(condition(), message)
        print("PASS: \(message)")
    }

    static func main() {
        setbuf(stdout, nil)
        for background: CGFloat in [0.12, 0.35, 0.8, 0.95] {
            let result = MenuBarGlyphImage.make(from: makeImage(background: background))!
            check(result.isTemplate, "monochrome glyph is a template on background \(background)")
            let pixels = [UInt8](result.image.dataProvider!.data! as Data)
            check(pixels[3] == 0, "background is transparent")
            check(pixels[(24 * 48 + 24) * 4 + 3] > 240, "solid glyph survives")
            check((0..<48).filter { pixels[($0 * 48 + 4) * 4 + 3] > 200 }.count >= 10, "one-pixel stroke survives")
        }
        let colored = MenuBarGlyphImage.make(from: makeImage(background: 0.2, colored: true))!
        check(!colored.isTemplate, "colored glyph is not flattened to a template")
        let pixels = [UInt8](colored.image.dataProvider!.data! as Data)
        check(pixels[3] == 0, "colored glyph has a transparent background")
        let center = (24 * 48 + 24) * 4
        print("Colored center RGBA: \(Array(pixels[center..<(center + 4)]))")
        check(pixels[center] > 200 && pixels[center + 1] < 40, "colored glyph retains its red foreground")
        check(MenuBarGlyphImage.make(from: makeImage(background: 0.3, empty: true)) == nil, "blank capture is rejected")
        check(MenuBarGlyphImage.make(from: makeImage(background: 0.3, strokeOnly: true)) != nil, "a sparse glyph is not mistaken for an empty image")

        if CommandLine.arguments.count > 2 {
            let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL, nil)!
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)!
            let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[2])
            let fixtures: [(String, CGRect)] = [
                ("volume", CGRect(x: 1273, y: 4, width: 24, height: 24)),
                ("fan", CGRect(x: 1311, y: 4, width: 24, height: 24)),
                ("wifi", CGRect(x: 1393, y: 5, width: 22, height: 22)),
                ("battery", CGRect(x: 1431, y: 5, width: 26, height: 22)),
                ("spotlight", CGRect(x: 1464, y: 4, width: 34, height: 24)),
                ("input", CGRect(x: 1496, y: 4, width: 46, height: 24)),
            ]
            for (name, bounds) in fixtures {
                let rect = bounds.applying(CGAffineTransform(scaleX: 2, y: 2))
                let crop = image.cropping(to: rect)!
                let result = MenuBarGlyphImage.make(from: crop)!
                let destination = CGImageDestinationCreateWithURL(outputDirectory.appendingPathComponent("\(name)-glyph.png") as CFURL, "public.png" as CFString, 1, nil)!
                CGImageDestinationAddImage(destination, result.image, nil)
                precondition(CGImageDestinationFinalize(destination))
                print("Real fixture \(name): template=\(result.isTemplate)")
            }
        }
    }
}
