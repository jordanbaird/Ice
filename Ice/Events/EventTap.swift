//
//  EventTap.swift
//  Ice
//

import Cocoa
import OSLog

/// A type that receives system events from various locations within the
/// event stream.
final class EventTap {
    /// Constants that specify the possible tapping locations for events.
    enum Location {
        /// The location where HID system events enter the window server.
        case hidEventTap

        /// The location where HID system and remote control events enter
        /// a login session.
        case sessionEventTap

        /// The location where session events have been annotated to flow
        /// to an application.
        case annotatedSessionEventTap

        /// The location where annotated events are delivered to a specific
        /// process.
        case pid(pid_t)

        var logString: String {
            switch self {
            case .hidEventTap: "HID event tap"
            case .sessionEventTap: "session event tap"
            case .annotatedSessionEventTap: "annotated session event tap"
            case .pid(let pid): "PID \(pid)"
            }
        }
    }

    private static let logger = Logger(category: "EventTap")
    private static let concurrentQueue = DispatchQueue(
        label: "EventTap.concurrentQueue",
        qos: .userInteractive,
        attributes: .concurrent
    )

    private static let eventTapCallBack: CGEventTapCallBack = { _, type, event, refcon in
        concurrentQueue.sync {
            guard let refcon else {
                return Unmanaged.passUnretained(event)
            }
            let tap: EventTap = Unmanaged.fromOpaque(refcon).takeUnretainedValue()
            return tap.callbackQueue.sync {
                if type == .tapDisabledByUserInput || type == .tapDisabledByTimeout {
                    tap.enable()
                    return nil
                }
                guard tap.isEnabled else {
                    return Unmanaged.passUnretained(event)
                }
                return tap.callback(tap, event).map { eventFromCallback in
                    Unmanaged.passUnretained(eventFromCallback)
                }
            }
        }
    }

    private var machPort: CFMachPort?
    private var runLoop: CFRunLoop?
    private var source: CFRunLoopSource?
    private let callback: (EventTap, CGEvent) -> CGEvent?

    /// The label associated with the event tap.
    let label: String

    /// The queue that performs the tap's callback.
    var callbackQueue: DispatchQueue

    /// A Boolean value that indicates whether the event tap is enabled.
    var isEnabled: Bool {
        guard let machPort else {
            return false
        }
        return CGEvent.tapIsEnabled(tap: machPort)
    }

    /// Creates a new event tap for the given event types.
    ///
    /// - Parameters:
    ///   - label: The label associated with the tap.
    ///   - options: A constant that specifies whether the tap is an active
    ///     filter or a passive listener.
    ///   - location: The location of the tap.
    ///   - placement: The placement of the tap relative to other active taps.
    ///   - types: The set of event types observed by the tap.
    ///   - callbackQueue: A dispatch queue that performs the tap's callback.
    ///   - callback: A callback function to perform when events are received.
    init(
        label: String = #function,
        options: CGEventTapOptions,
        location: Location,
        placement: CGEventTapPlacement,
        types: Set<CGEventType>,
        callbackQueue: DispatchQueue? = nil,
        callback: @escaping (_ tap: EventTap, _ event: CGEvent) -> CGEvent?
    ) {
        self.label = label
        self.callback = callback
        self.callbackQueue = callbackQueue ?? DispatchQueue(label: label)

        guard
            let machPort = createMachPort(
                location: location,
                placement: placement,
                options: options,
                types: types
            ),
            let runLoop = CFRunLoopGetCurrent(),
            let source = CFMachPortCreateRunLoopSource(nil, machPort, 0)
        else {
            EventTap.logger.error(#"Error creating event tap "\#(label, privacy: .public)""#)
            return
        }

        CFRunLoopAddSource(runLoop, source, .commonModes)

        self.machPort = machPort
        self.runLoop = runLoop
        self.source = source
    }

    /// Creates a new event tap for a single event type.
    ///
    /// - Parameters:
    ///   - label: The label associated with the tap.
    ///   - options: A constant that specifies whether the tap is an active
    ///     filter or a passive listener.
    ///   - location: The location of the tap.
    ///   - placement: The placement of the tap relative to other active taps.
    ///   - types: The event type observed by the tap.
    ///   - callbackQueue: A dispatch queue that performs the tap's callback.
    ///   - callback: A callback function to perform when events are received.
    convenience init(
        label: String = #function,
        options: CGEventTapOptions,
        location: Location,
        placement: CGEventTapPlacement,
        type: CGEventType,
        callbackQueue: DispatchQueue? = nil,
        callback: @escaping (_ tap: EventTap, _ event: CGEvent) -> CGEvent?
    ) {
        self.init(
            label: label,
            options: options,
            location: location,
            placement: placement,
            types: [type],
            callbackQueue: callbackQueue,
            callback: callback
        )
    }

    deinit {
        if let runLoop, let source {
            CFRunLoopRemoveSource(runLoop, source, .commonModes)
        }
        if let machPort {
            CGEvent.tapEnable(tap: machPort, enable: false)
            CFMachPortInvalidate(machPort)
        }
    }

    private func createMachPort(
        location: Location,
        placement: CGEventTapPlacement,
        options: CGEventTapOptions,
        types: Set<CGEventType>
    ) -> CFMachPort? {
        func createEventMask() -> CGEventMask {
            types.reduce(0) { $0 | (1 << $1.rawValue) }
        }

        func createUserInfo() -> UnsafeMutableRawPointer {
            Unmanaged.passUnretained(self).toOpaque()
        }

        func createMachPortForLocation(_ location: CGEventTapLocation) -> CFMachPort? {
            CGEvent.tapCreate(
                tap: location,
                place: placement,
                options: options,
                eventsOfInterest: createEventMask(),
                callback: EventTap.eventTapCallBack,
                userInfo: createUserInfo()
            )
        }

        func createMachPortForPid(_ pid: pid_t) -> CFMachPort? {
            CGEvent.tapCreateForPid(
                pid: pid,
                place: placement,
                options: options,
                eventsOfInterest: createEventMask(),
                callback: EventTap.eventTapCallBack,
                userInfo: createUserInfo()
            )
        }

        switch location {
        case .hidEventTap:
            return createMachPortForLocation(.cghidEventTap)
        case .sessionEventTap:
            return createMachPortForLocation(.cgSessionEventTap)
        case .annotatedSessionEventTap:
            return createMachPortForLocation(.cgAnnotatedSessionEventTap)
        case .pid(let pid):
            return createMachPortForPid(pid)
        }
    }

    /// Enables the event tap.
    func enable() {
        guard let machPort else { return }
        CGEvent.tapEnable(tap: machPort, enable: true)
    }

    /// Disables the event tap.
    func disable() {
        guard let machPort else { return }
        CGEvent.tapEnable(tap: machPort, enable: false)
    }
}
