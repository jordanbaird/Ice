//
//  HotKeyRegistry.swift
//  Ice
//

import Carbon.HIToolbox
import OSLog

enum HotKeyRegistry {
    enum EventKind {
        case keyUp
        case keyDown

        init?(event: EventRef) {
            switch Int(GetEventKind(event)) {
            case kEventHotKeyPressed:
                self = .keyDown
            case kEventHotKeyReleased:
                self = .keyUp
            default:
                return nil
            }
        }
    }

    struct EventHandler {
        let eventKind: EventKind
        let hotKeyRef: EventHotKeyRef
        let handler: () -> Void
    }

    private static var eventHandlers = [UInt32: EventHandler]()

    private static var eventHandlerRef: EventHandlerRef?

    private static let eventTypes: [EventTypeSpec] = [
        EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
        EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
    ]

    static let signature: OSType = {
        let code = "ICHK" // ICHK => Ice Hotkey
        return code.utf16.reduce(into: 0) { signature, byte in
            signature <<= 8
            signature += OSType(byte)
        }
    }()

    static var isInstalled: Bool {
        eventHandlerRef != nil
    }

    private static func installIfNeeded() -> OSStatus {
        guard eventHandlerRef == nil else {
            return noErr
        }
        let handler: EventHandlerUPP = { _, event, _ in
            Self.performEventHandler(for: event)
        }
        return InstallEventHandler(
            GetEventDispatcherTarget(),
            handler,
            eventTypes.count,
            eventTypes,
            nil,
            &eventHandlerRef
        )
    }

    static func register(_ hotKey: HotKey, eventKind: EventKind, handler: @escaping () -> Void) -> UInt32? {
        enum Context {
            static var currentID: UInt32 = 0
        }
        defer {
            Context.currentID += 1
        }

        var status = installIfNeeded()

        guard status == noErr else {
            Logger.hotKey.hotKeyError(.installationFailed.status(status))
            return nil
        }

        let id = Context.currentID

        guard eventHandlers[id] == nil else {
            Logger.hotKey.hotKeyError(.registrationFailed.reason("Event handler already stored for id \(id)"))
            return nil
        }

        var hotKeyRef: EventHotKeyRef?
        status = RegisterEventHotKey(
            UInt32(hotKey.key.rawValue),
            UInt32(hotKey.modifiers.carbonFlags),
            EventHotKeyID(signature: signature, id: id),
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )

        guard status == noErr else {
            Logger.hotKey.hotKeyError(.registrationFailed.status(status))
            return nil
        }

        guard let hotKeyRef else {
            Logger.hotKey.hotKeyError(.registrationFailed.reason("Invalid EventHotKeyRef"))
            return nil
        }

        let eventHandler = EventHandler(
            eventKind: eventKind,
            hotKeyRef: hotKeyRef,
            handler: handler
        )
        eventHandlers[id] = eventHandler

        return id
    }

    static func unregister(_ id: UInt32) {
        guard let eventHandler = eventHandlers.removeValue(forKey: id) else {
            return
        }
        let status = UnregisterEventHotKey(eventHandler.hotKeyRef)
        if status != noErr {
            Logger.hotKey.hotKeyError(.unregistrationFailed.status(status))
        }
    }

    static func performEventHandler(for event: EventRef?) -> OSStatus {
        guard let event else {
            return OSStatus(eventNotHandledErr)
        }

        // create a hot key id from the event
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )

        // make sure creation was successful
        guard status == noErr else {
            return status
        }

        // make sure the event signature matches our signature and
        // check that an event handler is registered for the event
        guard
            hotKeyID.signature == signature,
            let eventHandler = eventHandlers[hotKeyID.id],
            eventHandler.eventKind == EventKind(event: event)
        else {
            return OSStatus(eventNotHandledErr)
        }

        // all checks passed; perform the event handler
        eventHandler.handler()

        return noErr
    }
}
