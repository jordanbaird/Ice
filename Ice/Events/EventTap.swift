//
//  EventTap.swift
//  Ice
//

import Cocoa
import OSLog

/// A type that receives system events from various locations within the
/// event stream.
final class EventTap {
    /// Constants that specify the possible locations for an event tap.
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

        /// A string to use for logging purposes.
        var logString: String {
            switch self {
            case .hidEventTap: "HID event tap"
            case .sessionEventTap: "session event tap"
            case .annotatedSessionEventTap: "annotated session event tap"
            case .pid(let pid): "PID \(pid)"
            }
        }
    }

    /// Shared logger for event taps.
    private static let logger = Logger(category: "EventTap")

    /// Top level concurrent queue to run the shared event tap callback.
    private static let concurrentQueue = DispatchQueue.targetingGlobal(
        label: "EventTap.concurrentQueue",
        qos: .userInteractive,
        attributes: .concurrent
    )

    /// The shared event tap callback.
    private static let eventTapCallback: CGEventTapCallBack = { _, type, event, refcon in
        concurrentQueue.asyncAndWait {
            guard let refcon else {
                return Unmanaged.passUnretained(event)
            }
            let tap: EventTap = Unmanaged.fromOpaque(refcon).takeUnretainedValue()
            return tap.callbackQueue.asyncAndWait(flags: .barrier) {
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
    private var source: CFRunLoopSource?
    private let runLoop: CFRunLoop
    private let callbackQueue: DispatchQueue
    private let callback: (EventTap, CGEvent) -> CGEvent?

    /// The label associated with the event tap.
    let label: String

    /// A Boolean value that indicates whether the event tap is actively
    /// listening for events.
    var isEnabled: Bool {
        guard let machPort else { return false }
        return CGEvent.tapIsEnabled(tap: machPort)
    }

    /// A Boolean value that indicates whether the event tap is valid and
    /// able to receive events.
    var isValid: Bool {
        guard let machPort else { return false }
        return CFMachPortIsValid(machPort)
    }

    /// Creates a new event tap for the given event types.
    ///
    /// - Parameters:
    ///   - label: The label associated with the tap.
    ///   - options: A constant that specifies whether the tap is an active
    ///     filter or a passive listener.
    ///   - location: The location in the event stream to insert the tap.
    ///   - placement: The tap's placement relative to other active taps.
    ///   - types: Specifies the types of the events received by the tap.
    ///   - callbackQueue: A dispatch queue that performs the tap's callback.
    ///   - callback: A callback function to perform when events are received.
    init(
        label: String = #function,
        options: CGEventTapOptions,
        location: Location,
        placement: CGEventTapPlacement,
        types: [CGEventType],
        callbackQueue: DispatchQueue? = nil,
        callback: @escaping (_ tap: EventTap, _ event: CGEvent) -> CGEvent?
    ) {
        self.label = label
        self.callback = callback
        self.runLoop = RunLoop.current.getCFRunLoop()
        self.callbackQueue = callbackQueue ?? DispatchQueue(label: label)

        guard
            let machPort = EventTap.createMachPort(
                location: location,
                placement: placement,
                options: options,
                eventMask: types.reduce(0) { $0 | (1 << $1.rawValue) },
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            ),
            let source = CFMachPortCreateRunLoopSource(nil, machPort, 0)
        else {
            EventTap.logger.error(#"Error creating event tap "\#(label, privacy: .public)""#)
            return
        }

        self.machPort = machPort
        self.source = source
    }

    /// Creates a new event tap for a single event type.
    ///
    /// - Parameters:
    ///   - label: The label associated with the tap.
    ///   - options: A constant that specifies whether the tap is an active
    ///     filter or a passive listener.
    ///   - location: The location in the event stream to insert the tap.
    ///   - placement: The tap's placement relative to other active taps.
    ///   - type: Specifies the type of the events received by the tap.
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
        if let source {
            CFRunLoopRemoveSource(runLoop, source, .commonModes)
        }
        if let machPort {
            CGEvent.tapEnable(tap: machPort, enable: false)
            CFMachPortInvalidate(machPort)
        }
    }

    private static func createMachPort(
        location: Location,
        placement: CGEventTapPlacement,
        options: CGEventTapOptions,
        eventMask: CGEventMask,
        userInfo: UnsafeMutableRawPointer
    ) -> CFMachPort? {
        func createMachPort(location: CGEventTapLocation) -> CFMachPort? {
            CGEvent.tapCreate(
                tap: location,
                place: placement,
                options: options,
                eventsOfInterest: eventMask,
                callback: eventTapCallback,
                userInfo: userInfo
            )
        }

        func createMachPort(pid: pid_t) -> CFMachPort? {
            CGEvent.tapCreateForPid(
                pid: pid,
                place: placement,
                options: options,
                eventsOfInterest: eventMask,
                callback: eventTapCallback,
                userInfo: userInfo
            )
        }

        switch location {
        case .hidEventTap:
            return createMachPort(location: .cghidEventTap)
        case .sessionEventTap:
            return createMachPort(location: .cgSessionEventTap)
        case .annotatedSessionEventTap:
            return createMachPort(location: .cgAnnotatedSessionEventTap)
        case .pid(let pid):
            return createMachPort(pid: pid)
        }
    }

    /// Enables the event tap.
    func enable() {
        if let source {
            CFRunLoopAddSource(runLoop, source, .commonModes)
        }
        if let machPort {
            CGEvent.tapEnable(tap: machPort, enable: true)
        }
    }

    /// Disables the event tap.
    func disable() {
        if let source {
            CFRunLoopRemoveSource(runLoop, source, .commonModes)
        }
        if let machPort {
            CGEvent.tapEnable(tap: machPort, enable: false)
        }
    }
}
