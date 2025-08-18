//
//  EventTap.swift
//  Ice
//

import Cocoa
import OSLog

/// An object that receives events from a defined point in
/// the event stream.
final class EventTap {
    /// Constants that specify the possible insertion points
    /// for event taps.
    enum Location {
        /// The point where HID system events enter the window
        /// server.
        case hidEventTap

        /// The point where HID system and remote control events
        /// enter a login session.
        case sessionEventTap

        /// The point for session events that have been annotated
        /// to flow to an application.
        case annotatedSessionEventTap

        /// The point where events are delivered to the process
        /// with the specified identifier.
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

    /// Top level concurrent queue for efficient performance in
    /// the shared callback.
    private static let callbackQueue = DispatchQueue(
        label: "EventTap.callbackQueue",
        qos: .userInteractive,
        attributes: .concurrent
    )

    /// Shared callback for all event taps.
    private static let sharedCallback: CGEventTapCallBack = { _, type, event, refcon in
        guard let refcon else {
            return Unmanaged.passUnretained(event)
        }
        let tap: EventTap = Unmanaged.fromOpaque(refcon).takeUnretainedValue()
        let retained = Unmanaged.passRetained(tap)
        if type == .tapDisabledByUserInput || type == .tapDisabledByTimeout {
            retained.takeRetainedValue().enable()
            return nil
        }
        guard tap.isEnabled else {
            return Unmanaged.passUnretained(event)
        }
        return tap.callback(retained.takeRetainedValue(), event).map { eventFromCallback in
            Unmanaged.passUnretained(eventFromCallback)
        }
    }

//    private static let sharedCallback: CGEventTapCallBack = { _, type, event, refcon in
//        guard let refcon else {
//            return Unmanaged.passUnretained(event)
//        }
//        let tap: EventTap = Unmanaged.fromOpaque(refcon).takeUnretainedValue()
//        return callbackQueue.sync { [weak tap] in
//            guard let queue = tap?.queue else {
//                return Unmanaged.passUnretained(event)
//            }
//            return queue.sync { [weak tap] in
//                guard let tap else {
//                    return Unmanaged.passUnretained(event)
//                }
//                let retained = Unmanaged.passRetained(tap)
//                if type == .tapDisabledByUserInput || type == .tapDisabledByTimeout {
//                    retained.takeRetainedValue().enable()
//                    return nil
//                }
//                guard tap.isEnabled else {
//                    return Unmanaged.passUnretained(event)
//                }
//                return tap.callback(retained.takeRetainedValue(), event).map { eventFromCallback in
//                    Unmanaged.passUnretained(eventFromCallback)
//                }
//            }
//        }
//    }

    private var machPort: CFMachPort?
    private var source: CFRunLoopSource?
    private let runLoop: CFRunLoop
    private let queue: DispatchQueue
    private let callback: (EventTap, CGEvent) -> CGEvent?

    /// A string label that identifies the tap.
    let label: String

    /// A Boolean value that indicates whether the tap is actively
    /// listening for events.
    var isEnabled: Bool {
        guard let machPort else { return false }
        return CGEvent.tapIsEnabled(tap: machPort)
    }

    /// A Boolean value that indicates whether the tap is valid and
    /// able to receive events.
    var isValid: Bool {
        guard let machPort else { return false }
        return CFMachPortIsValid(machPort)
    }

    /// Creates a new event tap for the specified event types.
    ///
    /// If the tap is an active filter, the callback can return one
    /// of the following:
    ///   - The (possibly modified) received event to pass back to
    ///     the event stream.
    ///   - A new event to pass to the event stream in place of the
    ///     received event.
    ///   - `nil` to remove the received event from the event stream.
    ///
    /// If the tap is a passive listener, the callback's return value
    /// does not affect the event stream.
    ///
    /// - Parameters:
    ///   - label: A string label that identifies the tap in logging
    ///     and debugging contexts.
    ///   - types: The types of the events received by the tap.
    ///   - location: The point in the event stream to insert the tap.
    ///   - placement: The tap's placement relative to other active taps.
    ///   - option: An option that specifies whether the tap is an
    ///     active filter or a passive listener.
    ///   - queue: An optional target queue on which to execute the
    ///     tap's callback.
    ///   - callback: A closure for the tap to perform when events are
    ///     received.
    init(
        label: String = #function,
        types: [CGEventType],
        location: Location,
        placement: CGEventTapPlacement,
        option: CGEventTapOptions,
        queue: DispatchQueue? = nil,
        callback: @escaping (_ tap: EventTap, _ event: CGEvent) -> CGEvent?
    ) {
        self.label = label
        self.callback = callback
        self.runLoop = RunLoop.main.getCFRunLoop()
        self.queue = DispatchQueue(label: label, target: queue)

        guard
            let machPort = createMachPort(
                types: types,
                location: location,
                placement: placement,
                option: option
            ),
            let source = CFMachPortCreateRunLoopSource(nil, machPort, 0)
        else {
            EventTap.logger.error(#"Error creating event tap "\#(label, privacy: .public)""#)
            return
        }

        self.machPort = machPort
        self.source = source
    }

    /// Creates a new event tap for the specified event type.
    ///
    /// If the tap is an active filter, the callback can return one
    /// of the following:
    ///   - The (possibly modified) received event to pass back to
    ///     the event stream.
    ///   - A new event to pass to the event stream in place of the
    ///     received event.
    ///   - `nil` to remove the received event from the event stream.
    ///
    /// If the tap is a passive listener, the callback's return value
    /// does not affect the event stream.
    ///
    /// - Parameters:
    ///   - label: A string label that identifies the tap in logging
    ///     and debugging contexts.
    ///   - type: The type of the events received by the tap.
    ///   - location: The point in the event stream to insert the tap.
    ///   - placement: The tap's placement relative to other active taps.
    ///   - option: An option that specifies whether the tap is an
    ///     active filter or a passive listener.
    ///   - queue: An optional target queue on which to execute the
    ///     tap's callback.
    ///   - callback: A closure for the tap to perform when events are
    ///     received.
    convenience init(
        label: String = #function,
        type: CGEventType,
        location: Location,
        placement: CGEventTapPlacement,
        option: CGEventTapOptions,
        queue: DispatchQueue? = nil,
        callback: @escaping (_ tap: EventTap, _ event: CGEvent) -> CGEvent?
    ) {
        self.init(
            label: label,
            types: [type],
            location: location,
            placement: placement,
            option: option,
            queue: queue,
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

    private func createMachPort(
        types: [CGEventType],
        location: Location,
        placement: CGEventTapPlacement,
        option: CGEventTapOptions
    ) -> CFMachPort? {
        func createEventMask() -> CGEventMask {
            types.reduce(0) { $0 | (1 << $1.rawValue) }
        }

        func createUserInfo() -> UnsafeMutableRawPointer {
            Unmanaged.passUnretained(self).toOpaque()
        }

        func createMachPort(at tapLocation: CGEventTapLocation) -> CFMachPort? {
            CGEvent.tapCreate(
                tap: tapLocation,
                place: placement,
                options: option,
                eventsOfInterest: createEventMask(),
                callback: EventTap.sharedCallback,
                userInfo: createUserInfo()
            )
        }

        func createMachPort(for pid: pid_t) -> CFMachPort? {
            CGEvent.tapCreateForPid(
                pid: pid,
                place: placement,
                options: option,
                eventsOfInterest: createEventMask(),
                callback: EventTap.sharedCallback,
                userInfo: createUserInfo()
            )
        }

        switch location {
        case .hidEventTap:
            return createMachPort(at: .cghidEventTap)
        case .sessionEventTap:
            return createMachPort(at: .cgSessionEventTap)
        case .annotatedSessionEventTap:
            return createMachPort(at: .cgAnnotatedSessionEventTap)
        case .pid(let pid):
            return createMachPort(for: pid)
        }
    }

    /// Enables the event tap.
    func enable() {
        guard let source, let machPort else { return }
        CGEvent.tapEnable(tap: machPort, enable: true)
        CFRunLoopAddSource(runLoop, source, .commonModes)
    }

    /// Disables the event tap.
    func disable() {
        guard let source, let machPort else { return }
        CFRunLoopRemoveSource(runLoop, source, .commonModes)
        CGEvent.tapEnable(tap: machPort, enable: false)
    }
}
