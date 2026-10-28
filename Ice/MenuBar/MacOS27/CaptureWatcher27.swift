//
//  CaptureWatcher27.swift
//  Ice
//

import CoreAudio
import CoreMediaIO
import Foundation

/// Watches whether the camera or the microphone is in use.
///
/// Asks the devices themselves — `kCMIODevicePropertyDeviceIsRunningSomewhere` and the audio
/// equivalent — which answer for every application, not just this one, and need no permission:
/// nothing is opened, so neither Camera nor Microphone access is asked for and no indicator of
/// Ice's own appears. Measured on macOS 27.0: with nothing running both answer false, and the
/// microphone answers true for a call held in another application.
///
/// It asks rather than subscribes, and only while Ice is hiding something. Two local queries
/// every couple of seconds cost nothing worth measuring, and when nothing is concealed macOS
/// draws its own indicator and there is nothing for Ice to do.
@MainActor
final class CaptureWatcher27: ObservableObject {
    /// What is in use right now, as far as the last reading goes.
    @Published private(set) var kind: CaptureIndicator27.Kind?

    private var timer: Timer?

    /// How often the devices are asked while Ice is hiding something.
    private static let interval: TimeInterval = 2

    /// Starts or stops watching. Stopping clears what was last seen.
    func setWatching(_ watching: Bool) {
        guard watching != (timer != nil) else {
            return
        }
        guard watching else {
            timer?.invalidate()
            timer = nil
            kind = nil
            return
        }
        read()
        let timer = Timer(timeInterval: Self.interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.read()
            }
        }
        // The common run loop mode, or the reading stops while a menu is open.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func read() {
        kind = CaptureIndicator27.kind(
            cameraInUse: Self.isCameraInUse(),
            microphoneInUse: Self.isMicrophoneInUse()
        )
    }

    // MARK: Devices

    private static func isCameraInUse() -> Bool {
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        var size: UInt32 = 0
        guard
            CMIOObjectGetPropertyDataSize(CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil, &size) == 0,
            size > 0
        else {
            return false
        }
        var devices = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(
            CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil, size, &used, &devices
        ) == 0 else {
            return false
        }
        return devices.contains { device in
            var running = CMIOObjectPropertyAddress(
                mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
                mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
            )
            var value: UInt32 = 0
            var answered: UInt32 = 0
            let valueSize = UInt32(MemoryLayout<UInt32>.size)
            return CMIOObjectGetPropertyData(device, &running, 0, nil, valueSize, &answered, &value) == 0 && value != 0
        }
    }

    /// How many channels a device can record on. None means it cannot record at all.
    private static func inputChannels(of device: AudioObjectID) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard
            AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == 0,
            size > 0
        else {
            return 0
        }
        let buffer = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { buffer.deallocate() }
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, buffer) == 0 else {
            return 0
        }
        let list = UnsafeMutableAudioBufferListPointer(buffer.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    private static func isMicrophoneInUse() -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard
            AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == 0,
            size > 0
        else {
            return false
        }
        var devices = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &devices
        ) == 0 else {
            return false
        }
        return devices.contains { device in
            // Output devices answer the same question about playback — headphones playing music
            // report themselves as running — so only the ones that can record are asked. The size
            // of the input stream configuration is no test of that: a device with no input at all
            // still answers with an empty `AudioBufferList`, which is why playing through the
            // headphones used to light the microphone indicator. Count the channels.
            guard inputChannels(of: device) > 0 else {
                return false
            }
            var running = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var value: UInt32 = 0
            var valueSize = UInt32(MemoryLayout<UInt32>.size)
            return AudioObjectGetPropertyData(device, &running, 0, nil, &valueSize, &value) == 0 && value != 0
        }
    }
}
