// PantryEvent.swift — what a diagram `event` becomes in Swift (CLAUDE.md mapping):
// an AsyncStream on the record type plus a NotificationCenter name.

import Foundation

/// One named event carrying a value. `emit` posts it; `stream` delivers it to
/// however many listeners want it, in order, on their own tasks.
public struct PantryEvent<Value: Sendable>: Sendable {
    public let name: Notification.Name

    public init(_ name: String) {
        self.name = Notification.Name(name)
    }

    /// Post the event. Listeners on `stream` and on `NotificationCenter` both see it.
    public func emit(_ value: Value) {
        NotificationCenter.default.post(name: name, object: nil, userInfo: ["value": value])
    }

    /// Every future emission, until the consuming task is cancelled.
    public var stream: AsyncStream<Value> {
        AsyncStream { continuation in
            let token = Token(NotificationCenter.default.addObserver(forName: name, object: nil, queue: nil) { note in
                if let value = note.userInfo?["value"] as? Value { continuation.yield(value) }
            })
            continuation.onTermination = { _ in token.cancel() }
        }
    }

    /// The observer handle, boxed so the termination closure can carry it across isolation.
    private final class Token: @unchecked Sendable {
        private let observer: any NSObjectProtocol
        init(_ observer: any NSObjectProtocol) { self.observer = observer }
        func cancel() { NotificationCenter.default.removeObserver(observer) }
    }
}
