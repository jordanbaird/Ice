#!/usr/bin/env python3
"""Check the production image type and merge policy without a test target."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source = (root / "Ice/MenuBar/MenuBarItems/MenuBarItemImageCache.swift").read_text()
image_type = source.split("struct CapturedImage:", 1)[1].split(
    "/// The result of an image capture operation.", 1
)[0]
merge = next(line.strip() for line in source.splitlines()
             if line.strip().startswith("images.merge(newImages)"))
check = """
import AppKit
struct CapturedImage: IMAGE_TYPE
let context = CGContext(data: nil, width: 40, height: 40,
    bitsPerComponent: 8, bytesPerRow: 160, space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
context.fill(CGRect(x: 0, y: 0, width: 40, height: 20))
context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
context.fill(CGRect(x: 0, y: 20, width: 20, height: 20))
let image = context.makeImage()!
func checkFallbacks() {
    let icon = NSImage(cgImage: image, size: CGSize(width: 20, height: 20))
    for ambientScale: CGFloat in [1, 2] {
        let ambient = CGContext(data: nil, width: 80, height: 80,
            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ambient.scaleBy(x: ambientScale, y: ambientScale)
        let previous = NSGraphicsContext.current
        NSGraphicsContext.saveGraphicsState()
        let graphics = NSGraphicsContext(cgContext: ambient, flipped: false)
        NSGraphicsContext.current = graphics
        for scale: CGFloat in [1, 2] {
            let fallback = CapturedImage.fallback(icon: icon, scale: scale)!
            precondition(fallback.cgImage.width == Int(20 * scale))
            precondition(fallback.cgImage.height == Int(20 * scale))
            precondition(fallback.scaledSize == CGSize(width: 20, height: 20))
            precondition(fallback.nsImage.size == CGSize(width: 20, height: 20))
            precondition(fallback.isFallback)
            precondition(NSGraphicsContext.current === graphics)
            precondition(ambient.ctm == CGAffineTransform(scaleX: ambientScale, y: ambientScale))
            let probe = CGContext(data: nil, width: 4, height: 4,
                bitsPerComponent: 8, bytesPerRow: 16, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            probe.interpolationQuality = .none
            probe.draw(fallback.cgImage, in: CGRect(x: 0, y: 0, width: 4, height: 4))
            let pixels = probe.data!.assumingMemoryBound(to: UInt8.self)
            precondition(stride(from: 3, to: 64, by: 4).contains { pixels[$0] > 0 },
                "The fallback must contain visible pixels")
        }
        NSGraphicsContext.restoreGraphicsState()
        precondition(NSGraphicsContext.current === previous)
    }
}
checkFallbacks()
let actual = CapturedImage(cgImage: image, scale: 2)
let fallback = CapturedImage.fallback(
    icon: NSImage(cgImage: image, size: CGSize(width: 20, height: 20)), scale: 2)!
precondition(actual.scaledSize == CGSize(width: 20, height: 20))
precondition(fallback.nsImage.size == CGSize(width: 20, height: 20))
var images: [String: CapturedImage] = [:]
var newImages = ["icon": fallback]
MERGE
precondition(images["icon"]!.isFallback, "Missing images must accept fallbacks")
newImages = ["icon": actual]
MERGE
precondition(!images["icon"]!.isFallback, "Real captures must replace fallbacks")
newImages = ["icon": fallback]
MERGE
precondition(!images["icon"]!.isFallback, "Fallbacks must not overwrite real captures")
DispatchQueue.global().async {
    checkFallbacks()
    print("PASS: fallback pixels, logical size, context restoration, background rendering, cache merge")
    exit(0)
}
dispatchMain()
""".replace("IMAGE_TYPE", image_type).replace("MERGE", merge)
with tempfile.TemporaryDirectory(prefix="ice-image-cache-check-") as temporary:
    path = Path(temporary) / "main.swift"
    path.write_text(check)
    subprocess.run(["xcrun", "swift", str(path)], check=True, cwd=temporary)
