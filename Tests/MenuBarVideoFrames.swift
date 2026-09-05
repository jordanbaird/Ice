// Offline diagnostic extraction only; NOT part of Ice's application target.
// Compile with SDK 27:
//   xcrun swiftc -parse-as-library Tests/MenuBarVideoFrames.swift -o <tool>
// Usage: <tool> </absolute/input.mov> </tmp/existing-output-directory>
//
// Reads a local, existing video and writes new PNG diagnostic artifacts only.
// No capture, UI, audio playback, permissions, input events, or app control.
// Output must resolve to an existing subdirectory of /tmp; existing frame files
// are never overwritten. A failed extraction keeps already generated frames.
// Clips are limited to 60 seconds so an accidental long input stays bounded.
//
// Decodes the track sequentially with AVAssetReaderTrackOutput. Every real
// decoded video sample produces one PNG and an exact PTS entry in frames.tsv.
// No seeking, uniform resampling, duplicated frames or interpolated images.
// Pixel-buffer dimensions are retained without applying track rotation,
// resizing, cropping, overlays or contact-sheet composition. Requested decoder
// output is BGRA8; this diagnostic does not claim lossless HDR color recovery.

import AVFoundation
import Foundation
import ImageIO
import UniformTypeIdentifiers

private enum FrameError: Error, CustomStringConvertible {
    case arguments, inputUnavailable, outputUnavailable, invalidDuration, videoUnavailable
    case existingOutput(String), encodingFailed(String), readingFailed(String), invalidSample

    var description: String {
        switch self {
        case .arguments: "Usage: <tool> </absolute/input.mov> </tmp/existing-output-directory>"
        case .inputUnavailable: "Input must be an existing local regular file at an absolute path."
        case .outputUnavailable: "Output must be an existing subdirectory resolving beneath /tmp."
        case .invalidDuration: "A finite video duration greater than zero and no longer than 60 seconds is required."
        case .videoUnavailable: "No video track with valid natural dimensions was found."
        case .existingOutput(let path): "Refusing to overwrite existing output: \(path)"
        case .encodingFailed(let name): "Cannot encode PNG for \(name)."
        case .readingFailed(let error): "Sequential video read failed: \(error)"
        case .invalidSample: "A decoded sample has no valid PTS or BGRA pixel buffer."
        }
    }
}

@main
enum MenuBarVideoFrames {
    static func main() async {
        do {
            try await extract()
        } catch {
            fputs("Stopped: \(error)\n", stderr)
            exit(1)
        }
    }

    private static func extract() async throws {
        let args = Array(CommandLine.arguments.dropFirst())
        guard args.count == 2, args.allSatisfy({ $0.hasPrefix("/") }) else { throw FrameError.arguments }
        let files = FileManager.default
        let input = URL(fileURLWithPath: args[0]).standardizedFileURL.resolvingSymlinksInPath()
        guard try input.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
            throw FrameError.inputUnavailable
        }
        let output = URL(fileURLWithPath: args[1], isDirectory: true).standardizedFileURL.resolvingSymlinksInPath()
        let tempRoot = URL(fileURLWithPath: "/tmp", isDirectory: true).resolvingSymlinksInPath()
        guard output.path.hasPrefix(tempRoot.path + "/"),
              try output.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else {
            throw FrameError.outputUnavailable
        }

        let asset = AVURLAsset(url: input)
        let duration = try await asset.load(.duration)
        let seconds = duration.seconds
        guard seconds.isFinite, seconds > 0, seconds <= 60 else { throw FrameError.invalidDuration }
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw FrameError.videoUnavailable }
        let naturalSize = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let formats = try await track.load(.formatDescriptions)
        guard naturalSize.width.isFinite, naturalSize.height.isFinite,
              naturalSize.width > 0, naturalSize.height > 0 else { throw FrameError.videoUnavailable }
        let displaySize = CGRect(origin: .zero, size: naturalSize).applying(transform).standardized.size

        let manifest = output.appendingPathComponent("frames.tsv")
        guard !files.fileExists(atPath: manifest.path) else { throw FrameError.existingOutput(manifest.path) }
        for existing in try files.contentsOfDirectory(atPath: output.path) where existing.hasPrefix("frame-") {
            throw FrameError.existingOutput(output.appendingPathComponent(existing).path)
        }

        print(String(format: "Asset duration: %.6f s; natural pixels: %.0f x %.0f; oriented dimensions: %.0f x %.0f",
                     seconds, naturalSize.width, naturalSize.height, displaySize.width, displaySize.height))
        for format in formats {
            let code = CMFormatDescriptionGetMediaSubType(format)
            let fourCC = String(bytes: [24, 16, 8, 0].map { UInt8((code >> $0) & 0xff) }, encoding: .ascii) ?? "\(code)"
            print("Video codec: \(fourCC); encoded dimensions: \(CMVideoFormatDescriptionGetDimensions(format))")
        }
        print("Sequential decoding of actual samples; no resampling; raw encoded orientation; output: \(output.path)")
        fflush(stdout)
        let reader = try AVAssetReader(asset: asset)
        let trackOutput = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ])
        guard reader.canAdd(trackOutput) else { throw FrameError.readingFailed("reader cannot add this video output") }
        reader.add(trackOutput)
        try decode(reader: reader, trackOutput: trackOutput, output: output, manifest: manifest)
    }

    private static func decode(reader: AVAssetReader, trackOutput: AVAssetReaderTrackOutput, output: URL, manifest: URL) throws {
        guard reader.startReading() else { throw FrameError.readingFailed(String(describing: reader.error)) }
        defer { if reader.status == .reading { reader.cancelReading() } }
        var index = 0
        var markers = 0
        var rows = ["index\tpts_value\tpts_timescale\tpts_ms\tduration_value\tduration_timescale\twidth\theight\tfile"]
        while let sample = trackOutput.copyNextSampleBuffer() {
            if CMSampleBufferGetNumSamples(sample) == 0 {
                markers += 1
                continue
            }
            try autoreleasepool {
                let pts = CMSampleBufferGetPresentationTimeStamp(sample)
                let duration = CMSampleBufferGetDuration(sample)
                guard pts.isValid, pts.seconds.isFinite,
                      let pixels = CMSampleBufferGetImageBuffer(sample) else { throw FrameError.invalidSample }
                let image = try image(from: pixels)
                let name = String(format: "frame-%04d-%012.3fms.png", index, pts.seconds * 1000)
                let data = NSMutableData()
                guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
                    throw FrameError.encodingFailed(name)
                }
                CGImageDestinationAddImage(destination, image, nil)
                guard CGImageDestinationFinalize(destination) else { throw FrameError.encodingFailed(name) }
                try (data as Data).write(to: output.appendingPathComponent(name), options: .withoutOverwriting)
                rows.append("\(index)\t\(pts.value)\t\(pts.timescale)\t\(String(format: "%.6f", pts.seconds * 1000))\t\(duration.value)\t\(duration.timescale)\t\(image.width)\t\(image.height)\t\(name)")
                print(String(format: "%@: PTS=%lld/%d (%.6f ms); pixels=%d x %d", name, pts.value, pts.timescale, pts.seconds * 1000, image.width, image.height))
                index += 1
            }
            fflush(stdout)
        }
        try Data((rows.joined(separator: "\n") + "\n").utf8).write(to: manifest, options: .withoutOverwriting)
        print("Reader status: \(reader.status.rawValue); \(index) decoded PNGs; \(markers) marker-only samples; PTS manifest: \(manifest.path)")
        guard reader.status == .completed else {
            throw FrameError.readingFailed(String(describing: reader.error))
        }
        print("Finished: all actual samples decoded sequentially. Input was not modified.")
    }

    private static func image(from pixels: CVPixelBuffer) throws -> CGImage {
        guard CVPixelBufferGetPixelFormatType(pixels) == kCVPixelFormatType_32BGRA,
              CVPixelBufferLockBaseAddress(pixels, .readOnly) == kCVReturnSuccess else { throw FrameError.invalidSample }
        defer { CVPixelBufferUnlockBaseAddress(pixels, .readOnly) }
        let width = CVPixelBufferGetWidth(pixels)
        let height = CVPixelBufferGetHeight(pixels)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixels)
        guard width > 0, height > 0, bytesPerRow >= width * 4,
              let base = CVPixelBufferGetBaseAddress(pixels),
              let provider = CGDataProvider(data: Data(bytes: base, count: bytesPerRow * height) as CFData),
              let image = CGImage(
                width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: bytesPerRow,
                space: CVImageBufferGetColorSpace(pixels)?.takeUnretainedValue() ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue).union(.byteOrder32Little),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
              ) else { throw FrameError.invalidSample }
        return image
    }
}
