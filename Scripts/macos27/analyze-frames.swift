// For each PNG in a directory, prints: name, leftmost lit column (points), lit width (points).
// usage: analyze-frames <dir> <originX> <widthPoints>
import Foundation
import ImageIO

let directory = CommandLine.arguments[1]
let originX = Double(CommandLine.arguments[2])!
let widthPoints = Double(CommandLine.arguments[3])!
let names = ((try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? [])
    .filter { $0.hasSuffix(".png") }
    .sorted()

for name in names {
    guard
        let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: "\(directory)/\(name)") as CFURL, nil),
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
        let context = CGContext(
            data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
            bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    else {
        continue
    }
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    let pixels = context.data!.assumingMemoryBound(to: UInt8.self)
    let scale = Double(image.width) / widthPoints
    let rows = Int(Double(image.height) * 0.25)..<Int(Double(image.height) * 0.75)
    var leftmost = -1
    var litColumns = 0
    for x in 0..<image.width {
        let lit = rows.contains { y in
            let i = (y * image.width + x) * 4
            return Int(pixels[i]) + Int(pixels[i + 1]) + Int(pixels[i + 2]) > 450
        }
        if lit {
            litColumns += 1
            if leftmost < 0 {
                leftmost = Int(originX + Double(x) / scale)
            }
        }
    }
    print(name.replacingOccurrences(of: ".png", with: ""), leftmost, Int(Double(litColumns) / scale))
}
