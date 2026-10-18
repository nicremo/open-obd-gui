import Foundation
import Synchronization

/// Calls every listener synchronously, in emission order. `AsyncStream` has a single consumer and delivers later,
/// so anything that must see all events of one operation before it returns listens here.
public final class EventFanout: Sendable {
    private let listeners = Mutex<[UUID: @Sendable (EngineEvent) -> Void]>([:])

    public init() {}

    public func add(_ listener: @escaping @Sendable (EngineEvent) -> Void) -> UUID {
        let token = UUID()
        listeners.withLock { $0[token] = listener }
        return token
    }

    public func remove(_ token: UUID) {
        _ = listeners.withLock { $0.removeValue(forKey: token) }
    }

    public func send(_ event: EngineEvent) {
        let current = listeners.withLock { Array($0.values) }
        current.forEach { $0(event) }
    }
}

/// Delivers each event to the observers first, then to the stream.
struct EventChannel: Sendable {
    let stream: AsyncStream<EngineEvent>.Continuation
    let observers: EventFanout

    func yield(_ event: EngineEvent) {
        observers.send(event)
        stream.yield(event)
    }

    func finish() {
        stream.finish()
    }
}
