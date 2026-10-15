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
context.fill(CGRect(x: 0, y: 0, width: 40, height: 40))
let image = context.makeImage()!
let actual = CapturedImage(cgImage: image, scale: 2)
let fallback = CapturedImage(cgImage: image, scale: 2, isFallback: true)
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
print("PASS: fallback insertion, capture replacement, capture retention, Retina size")
""".replace("IMAGE_TYPE", image_type).replace("MERGE", merge)
with tempfile.TemporaryDirectory(prefix="ice-image-cache-check-") as temporary:
    path = Path(temporary) / "main.swift"
    path.write_text(check)
    subprocess.run(["xcrun", "swift", str(path)], check=True, cwd=temporary)
