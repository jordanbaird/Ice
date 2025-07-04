//
//  HotkeyRegistry.swift
//  Ice
//

import Carbon.HIToolbox
import Cocoa
import Combine
import OSLog

/// An object that manages the registration, storage, and unregistration of hotkeys.
final class HotkeyRegistry {
    /// The event kinds that a hotkey can be registered for.
    enum EventKind {
        case keyUp
        case keyDown

        fileprivate init?(event: EventRef) {
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

    /// An object that stores the information needed to cancel a registration.
    private final class Registration {
        let eventKind: EventKind
        let key: KeyCode
        let modifiers: Modifiers
        let hotKeyID: EventHotKeyID
        var hotKeyRef: EventHotKeyRef?
        let handler: () -> Void

        init(
            eventKind: EventKind,
            key: KeyCode,
            modifiers: Modifiers,
            hotKeyID: EventHotKeyID,
            hotKeyRef: EventHotKeyRef,
            handler: @escaping () -> Void
        ) {
            self.eventKind = eventKind
            self.key = key
            self.modifiers = modifiers
            self.hotKeyID = hotKeyID
            self.hotKeyRef = hotKeyRef
            self.handler = handler
        }
    }

    private let signature = OSType(1231250720) // OSType for Ice

    private var eventHandlerRef: EventHandlerRef?

    private var registrations = [UInt32: Registration]()

    private var cancellables = Set<AnyCancellable>()

    /// Installs the global event handler reference, if it isn't already installed.
    private func installIfNeeded() -> OSStatus {
        guard eventHandlerRef == nil else {
            return noErr
        }

        NotificationCenter.default
            .publisher(for: NSMenu.didBeginTrackingNotification)
            .sink { [weak self] _ in
                self?.unregisterAndRetainAll()
            }
            .store(in: &cancellables)

        NotificationCenter.default
            .publisher(for: NSMenu.didEndTrackingNotification)
            .sink { [weak self] _ in
                self?.registerAllRetained()
            }
            .store(in: &cancellables)

        let handler: EventHandlerUPP = { _, event, userData in
            guard
                let event,
                let userData
            else {
                return OSStatus(eventNotHandledErr)
            }
            let registry = Unmanaged<HotkeyRegistry>.fromOpaque(userData).takeUnretainedValue()
            return registry.performEventHandler(for: event)
        }

        let eventTypes: [EventTypeSpec] = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]

        return InstallEventHandler(
            GetEventDispatcherTarget(),
            handler,
            eventTypes.count,
            eventTypes,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )
    }

    /// Registers the given hotkey for the given event kind and returns the
    /// identifier of the registration on success.
    ///
    /// The returned identifier can be used to unregister the hotkey using
    /// the ``unregister(_:)`` function.
    ///
    /// - Parameters:
    ///   - hotkey: The hotkey to register the handler with.
    ///   - eventKind: The event kind to register the handler with.
    ///   - handler: The handler to perform when `hotkey` is triggered with
    ///     the event kind specified by `eventKind`.
    ///
    /// - Returns: The registration's identifier on success, `nil` on failure.
    @MainActor
    func register(hotkey: Hotkey, eventKind: EventKind, handler: @escaping () -> Void) -> UInt32? {
        enum Context {
            static var currentID: UInt32 = 0
        }

        defer {
            Context.currentID += 1
        }

        guard let keyCombination = hotkey.keyCombination else {
            Logger.hotkeys.error("Hotkey does not have a valid key combination")
            return nil
        }

        var status = installIfNeeded()

        guard status == noErr else {
            Logger.hotkeys.error("Hotkey event handler installation failed with status \(status, privacy: .public)")
            return nil
        }

        let id = Context.currentID

        guard registrations[id] == nil else {
            Logger.hotkeys.error("Hotkey already registered for id \(id, privacy: .public)")
            return nil
        }

        let hotKeyID = EventHotKeyID(signature: signature, id: id)
        var hotKeyRef: EventHotKeyRef?
        status = RegisterEventHotKey(
            UInt32(keyCombination.key.rawValue),
            UInt32(keyCombination.modifiers.carbonFlags),
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )

        guard status == noErr else {
            Logger.hotkeys.error("Hotkey registration failed with status \(status, privacy: .public)")
            return nil
        }

        guard let hotKeyRef else {
            Logger.hotkeys.error("Hotkey registration failed due to invalid EventHotKeyRef")
            return nil
        }

        let registration = Registration(
            eventKind: eventKind,
            key: keyCombination.key,
            modifiers: keyCombination.modifiers,
            hotKeyID: hotKeyID,
            hotKeyRef: hotKeyRef,
            handler: handler
        )
        registrations[id] = registration

        return id
    }

    /// Unregisters the key combination with the given identifier, retaining
    /// its registration in an inactive state.
    private func retainedUnregister(_ id: UInt32) {
        guard let registration = registrations[id] else {
            Logger.hotkeys.error("No registered key combination for id \(id, privacy: .public)")
            return
        }
        let status = UnregisterEventHotKey(registration.hotKeyRef)
        guard status == noErr else {
            Logger.hotkeys.error("Hotkey unregistration failed with status \(status, privacy: .public)")
            return
        }
        registration.hotKeyRef = nil
    }

    /// Unregisters the key combination with the given identifier.
    ///
    /// - Parameter id: An identifier returned from a call to the
    ///   ``register(hotkey:eventKind:handler:)`` function.
    func unregister(_ id: UInt32) {
        retainedUnregister(id)
        registrations.removeValue(forKey: id)
    }

    /// Unregisters all key combinations, retaining their registrations
    /// in an inactive state.
    private func unregisterAndRetainAll() {
        for (id, _) in registrations {
            retainedUnregister(id)
        }
    }

    /// Registers all registrations that were retained during a call to
    /// ``retainedUnregister(_:)``
    private func registerAllRetained() {
        for registration in registrations.values {
            guard registration.hotKeyRef == nil else {
                continue
            }

            var hotKeyRef: EventHotKeyRef?
            let status = RegisterEventHotKey(
                UInt32(registration.key.rawValue),
                UInt32(registration.modifiers.carbonFlags),
                registration.hotKeyID,
                GetEventDispatcherTarget(),
                0,
                &hotKeyRef
            )

            guard
                status == noErr,
                let hotKeyRef
            else {
                registrations.removeValue(forKey: registration.hotKeyID.id)
                Logger.hotkeys.error("Hotkey registration failed with status \(status, privacy: .public)")
                continue
            }

            registration.hotKeyRef = hotKeyRef
        }
    }

    /// Retrieves and performs the event handler stored under the
    /// identifier for the specified event.
    private func performEventHandler(for event: EventRef?) -> OSStatus {
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
        // that an event handler is registered for the event
        guard
            hotKeyID.signature == signature,
            let registration = registrations[hotKeyID.id],
            registration.eventKind == EventKind(event: event)
        else {
            return OSStatus(eventNotHandledErr)
        }

        // all checks passed; perform the event handler
        registration.handler()

        return noErr
    }
}
