//
//  SendableEvent.swift
//  Ice
//

import Cocoa

/// A `Sendable` wrapper around an event.
@dynamicMemberLookup
struct SendableEvent<Event>: @unchecked Sendable {
    private let event: Event

    init(event: Event) where Event: NSEvent {
        self.event = event
    }

    init(event: Event) where Event: CGEvent {
        self.event = event
    }

    subscript<Value>(dynamicMember keyPath: KeyPath<Event, Value>) -> Value {
        event[keyPath: keyPath]
    }
}

/// A stream that yields events as they are received.
typealias EventStream<Event> = AsyncStream<SendableEvent<Event>>
