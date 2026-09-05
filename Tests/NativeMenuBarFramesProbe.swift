// Standalone diagnostic, NOT part of the Ice application target.
// Usage: native-menu-bar-frames-probe /tmp/<existing-empty-output-directory>
// Captures only the main display's top 40 points, at native pixel dimensions.
// No audio, input events, permission requests, application or preference edits.
// Requests are sequential, at most one per 30 ms, for a four-second window.
// A screenshot finishing after the deadline is discarded: an uninterruptible
// system call can delay process exit, but no out-of-window frame is retained.
// stdout timestamps bracket capture calls, not the display's exact scanout.

import CoreGraphics
import Darwin
import Foundation
import ImageIO
@preconcurrency import ScreenCaptureKit
import UniformTypeIdentifiers

private struct ProbeFailure: Error, CustomStringConvertible {
    let description: String
}

@main
enum NativeMenuBarFramesProbe {
    static func main() async {
        do {
            guard #available(macOS 26.0, *) else {
                throw ProbeFailure(description: "macOS 26 or newer is required.")
            }
            try await capture()
        } catch {
            FileHandle.standardError.write(Data("Error: \(error)\n".utf8))
            exit(1)
        }
    }

    @available(macOS 26.0, *)
    private static func capture() async throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard arguments.count == 1, arguments[0].hasPrefix("/tmp/") else {
            throw ProbeFailure(description: "Pass exactly one existing empty directory beneath /tmp/.")
        }
        let output = URL(fileURLWithPath: arguments[0], isDirectory: true)
            .standardizedFileURL.resolvingSymlinksInPath()
        let temporaryRoot = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .resolvingSymlinksInPath().path
        guard output.path.hasPrefix(temporaryRoot + "/"), output.path != temporaryRoot else {
            throw ProbeFailure(description: "The resolved output directory must remain beneath /tmp/.")
        }
        let directory = open(output.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard directory >= 0 else {
            throw ProbeFailure(description: "Cannot open the existing output directory.")
        }
        defer { close(directory) }
        var metadata = stat()
        guard fstat(directory, &metadata) == 0, metadata.st_uid == geteuid(),
              try FileManager.default.contentsOfDirectory(atPath: output.path).isEmpty else {
            throw ProbeFailure(description: "The output directory must be owned by this user and empty.")
        }
        guard CGPreflightScreenCaptureAccess() else {
            throw ProbeFailure(description: "Screen capture permission is unavailable; no permission was requested.")
        }

        let displayID = CGMainDisplayID()
        let display = CGDisplayBounds(displayID)
        let pixelWidth = CGDisplayPixelsWide(displayID)
        guard CGDisplayIsActive(displayID) != 0,
              [display.minX, display.minY, display.width, display.height].allSatisfy(\.isFinite),
              display.width > 0, display.height >= 40, pixelWidth > 0 else {
            throw ProbeFailure(description: "The main display is unavailable or has invalid geometry.")
        }
        let strip = CGRect(x: display.minX, y: display.minY, width: display.width, height: 40)
        let scale = CGFloat(pixelWidth) / display.width
        let pixelHeight = Int((strip.height * scale).rounded())
        let configuration = SCScreenshotConfiguration()
        configuration.showsCursor = false
        configuration.dynamicRange = .sdr
        configuration.displayIntent = .local
        configuration.width = pixelWidth
        configuration.height = pixelHeight
        // Leave fileURL nil: only our exclusive PNG writer may create files.

        let interval = 0.030
        let began = ProcessInfo.processInfo.systemUptime
        let deadline = began + 4
        var nextSample = began
        var saved = 0
        print("main_display=\(displayID) rect=\(strip) native_pixels=\(pixelWidth)x\(pixelHeight)")
        print(String(format: "capture_start_uptime=%.9f deadline_uptime=%.9f interval_ms=30", began, deadline))
        print("frame,before_uptime,after_uptime,before_elapsed_ms,after_elapsed_ms,width,height,file")
        fflush(stdout)

        for index in 0 ..< 134 {
            let remainingWait = nextSample - ProcessInfo.processInfo.systemUptime
            if remainingWait > 0 {
                try await Task.sleep(for: .nanoseconds(Int64(remainingWait * 1_000_000_000)))
            }
            guard ProcessInfo.processInfo.systemUptime < deadline else { break }
            guard CGMainDisplayID() == displayID, CGDisplayBounds(displayID) == display,
                  CGDisplayPixelsWide(displayID) == pixelWidth else {
                throw ProbeFailure(description: "Main display geometry changed; stopped without expanding the capture region.")
            }
            guard CGPreflightScreenCaptureAccess() else {
                throw ProbeFailure(description: "Screen capture permission is no longer available; stopped without requesting it.")
            }

            let before = ProcessInfo.processInfo.systemUptime
            guard before < deadline else { break }
            let screenshot = try await SCScreenshotManager.captureScreenshot(rect: strip, configuration: configuration)
            let after = ProcessInfo.processInfo.systemUptime
            guard after <= deadline else {
                print(String(format: "discarded_late_frame before_uptime=%.9f after_uptime=%.9f", before, after))
                fflush(stdout)
                break
            }
            guard CGMainDisplayID() == displayID, CGDisplayBounds(displayID) == display,
                  CGDisplayPixelsWide(displayID) == pixelWidth else {
                throw ProbeFailure(description: "Main display changed during capture; discarded the frame.")
            }
            guard let image = screenshot.sdrImage,
                  image.width == pixelWidth, image.height == pixelHeight else {
                throw ProbeFailure(description: "Screenshot dimensions do not match the native-size menu-bar strip.")
            }
            let filename = String(format: "frame-%03d.png", index)
            try writePNG(image, filename: filename, directory: directory)
            saved += 1
            print(String(format: "%d,%.9f,%.9f,%.3f,%.3f,%d,%d,%@",
                         index, before, after, (before - began) * 1000, (after - began) * 1000,
                         image.width, image.height, filename))
            fflush(stdout)
            nextSample = before + interval
        }
        print("complete saved_frames=\(saved); PNGs are unscaled; no audio or input events were used.")
        fflush(stdout)
    }

    private static func writePNG(_ image: CGImage, filename: String, directory: Int32) throws {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw ProbeFailure(description: "Cannot create the PNG encoder.")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw ProbeFailure(description: "Cannot encode the PNG frame.")
        }
        let file = openat(directory, filename, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, mode_t(0o600))
        guard file >= 0 else {
            throw ProbeFailure(description: "Refused to overwrite or follow a file at \(filename).")
        }
        defer { close(file) }
        var offset = 0
        while offset < data.length {
            let written = Darwin.write(file, data.bytes.advanced(by: offset), data.length - offset)
            if written < 0, errno == EINTR { continue }
            guard written > 0 else {
                throw ProbeFailure(description: "Could not finish writing \(filename).")
            }
            offset += written
        }
    }
}
