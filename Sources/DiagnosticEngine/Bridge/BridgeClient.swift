import AdapterKit
import Darwin
import FordKnowledge
import Foundation
import OBDCore
import Synchronization

/// The running app's session as a `DiagnosticBackend`. Every call goes over the bridge socket,
/// so the app shows progress and traffic while the agent reads.
public final class BridgeClient: DiagnosticBackend {
    public let hello: BridgeHello
    public let linkLabel: String
    public let knowledge: KnowledgeBase
    public let events: AsyncStream<EngineEvent>
    let connection: BridgeConnection

    /// True when an app answers on the socket. Does not send anything.
    public static func isReachable(at path: String = BridgeEndpoint.defaultPath) -> Bool {
        guard let fd = try? BridgeSocket.connect(to: path) else { return false }
        Darwin.close(fd)
        return true
    }

    /// Connects and exchanges the greeting. Throws `APP_NOT_RUNNING` when no app listens.
    public static func connect(at path: String = BridgeEndpoint.defaultPath, knowledge: KnowledgeBase = .bundled) async throws -> BridgeClient {
        let fd: Int32
        do {
            fd = try BridgeSocket.connect(to: path)
        } catch let error as BridgeError {
            throw error
        } catch {
            throw BridgeError.appNotRunning(path: path)
        }
        let (events, eventSink) = AsyncStream.makeStream(of: EngineEvent.self, bufferingPolicy: .bufferingNewest(2_000))
        let connection = BridgeConnection(channel: LineChannel(fd: fd), events: eventSink)
        let greeting: BridgeHello
        do {
            guard case .hello(let hello) = try await connection.call(.hello) else { throw BridgeError.protocolMismatch("keine Begrüßung") }
            guard hello.protocolVersion == BridgeEndpoint.protocolVersion else {
                throw BridgeError.protocolMismatch("App Version \(hello.protocolVersion), openobd Version \(BridgeEndpoint.protocolVersion)")
            }
            greeting = hello
        } catch {
            connection.close()
            throw error
        }
        return BridgeClient(hello: greeting, knowledge: knowledge, events: events, connection: connection)
    }

    private init(hello: BridgeHello, knowledge: KnowledgeBase, events: AsyncStream<EngineEvent>, connection: BridgeConnection) {
        self.hello = hello
        linkLabel = "app:\(hello.link)"
        self.knowledge = knowledge
        self.events = events
        self.connection = connection
    }

    public func connect() async throws -> AdapterSummary {
        try await expect(.connect) { if case .adapter(let value) = $0 { value } else { nil } }
    }

    public func scan(depth: ScanDepth) async throws -> VehicleReport {
        try await expect(.scan(depth: depth)) { if case .report(let value) = $0 { value } else { nil } }
    }

    public func discoverModules(buses: [BusKind], sweep: Bool) async throws -> [DiscoveredModule] {
        try await expect(.discoverModules(buses: buses, sweep: sweep)) { if case .modules(let value) = $0 { value } else { nil } }
    }

    public func readModuleTroubleCodes(request: UInt32, bus: BusKind) async throws -> [ReportDTC] {
        try await expect(.readModuleTroubleCodes(request: request, bus: bus)) { if case .troubleCodes(let value) = $0 { value } else { nil } }
    }

    public func readOBDTroubleCodes() async throws -> [ReportDTC] {
        try await expect(.readOBDTroubleCodes) { if case .troubleCodes(let value) = $0 { value } else { nil } }
    }

    public func identify(request: UInt32, bus: BusKind, full: Bool) async throws -> IdentificationResult {
        try await expect(.identify(request: request, bus: bus, full: full)) { if case .identification(let value) = $0 { value } else { nil } }
    }

    public func readDID(_ did: UInt16, request: UInt32, bus: BusKind) async throws -> DIDReading {
        try await expect(.readDID(did: did, request: request, bus: bus)) { if case .reading(let value) = $0 { value } else { nil } }
    }

    public func supportedPIDs() async throws -> [UInt32: Set<UInt8>] {
        try await expect(.supportedPIDs) { if case .supportedPIDs(let value) = $0 { value.mapValues(Set.init) } else { nil } }
    }

    public func readPIDs(_ pids: [UInt8]) async throws -> [MeasurementRecord] {
        try await expect(.readPIDs(pids: pids)) { if case .records(let value) = $0 { value } else { nil } }
    }

    public func rawRequest(_ payload: [UInt8], target: RequestTarget, bus: BusKind, timeout: Duration) async throws -> RequestResult {
        let operation = BridgeOperation.raw(payload: payload, target: target, bus: bus, timeoutMilliseconds: Int(timeout.wholeMilliseconds))
        return try await expect(operation) { if case .raw(let value) = $0 { value } else { nil } }
    }

    public func live(pids: [UInt8], interval: Duration) -> AsyncThrowingStream<MeasurementRecord, any Error> {
        connection.stream(.live(pids: pids, intervalMilliseconds: Int(interval.wholeMilliseconds)))
    }

    /// The report the app currently shows, if any.
    public func lastReport() async throws -> VehicleReport? {
        try await expect(.lastReport) { if case .lastReport(let value) = $0 { .some(value) } else { nil } }
    }

    /// Closes the socket. The app keeps its session.
    public func close() async {
        connection.close()
    }

    private func expect<T>(_ operation: BridgeOperation, _ extract: (BridgeResult) -> T?) async throws -> T {
        let result = try await connection.call(operation)
        guard let value = extract(result) else { throw BridgeError.protocolMismatch("unerwartete Antwort auf \(operation.title)") }
        return value
    }
}

/// Routes frames from the app to the waiting calls and streams.
final class BridgeConnection: Sendable {
    private enum Waiter: Sendable {
        case call(CheckedContinuation<BridgeResult, any Error>)
        case stream(AsyncThrowingStream<MeasurementRecord, any Error>.Continuation)
    }

    private struct State: Sendable {
        var waiters: [Int: Waiter] = [:]
        var closed = false
    }

    private let channel: LineChannel
    private let state = Mutex(State())
    private let nextID = Atomic(1)

    init(channel: LineChannel, events: AsyncStream<EngineEvent>.Continuation) {
        self.channel = channel
        Task { [self] in
            await route(events: events)
        }
    }

    func call(_ operation: BridgeOperation) async throws -> BridgeResult {
        let id = nextID.wrappingAdd(1, ordering: .relaxed).oldValue
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard register(id, .call(continuation)) else {
                    continuation.resume(throwing: BridgeError.disconnected)
                    return
                }
                send(.call(id: id, operation: operation), failing: id)
            }
        } onCancel: {
            send(.cancel(id: id), failing: nil)
        }
    }

    func stream(_ operation: BridgeOperation) -> AsyncThrowingStream<MeasurementRecord, any Error> {
        let id = nextID.wrappingAdd(1, ordering: .relaxed).oldValue
        return AsyncThrowingStream { continuation in
            guard register(id, .stream(continuation)) else {
                continuation.finish(throwing: BridgeError.disconnected)
                return
            }
            continuation.onTermination = { [self] termination in
                if case .cancelled = termination { send(.cancel(id: id), failing: nil) }
            }
            send(.call(id: id, operation: operation), failing: id)
        }
    }

    func close() {
        channel.close()
    }

    private func register(_ id: Int, _ waiter: Waiter) -> Bool {
        state.withLock { state in
            guard !state.closed else { return false }
            state.waiters[id] = waiter
            return true
        }
    }

    private func send(_ command: BridgeCommand, failing id: Int?) {
        do {
            try channel.send(BridgeCoding.line(command))
        } catch {
            if let id { finish(id, with: .failure(id: id, failure: .bridge(.disconnected))) }
        }
    }

    private func route(events: AsyncStream<EngineEvent>.Continuation) async {
        for await line in channel.incoming {
            guard let frame = try? BridgeCoding.decode(BridgeFrame.self, from: line) else { continue }
            switch frame {
            case .event(_, let event):
                events.yield(event)
            case .record(let id, let record):
                if case .stream(let continuation) = state.withLock({ $0.waiters[id] }) {
                    continuation.yield(record)
                }
            case .result(let id, _), .failure(let id, _):
                finish(id, with: frame)
            }
        }
        let orphans = state.withLock { state in
            state.closed = true
            defer { state.waiters = [:] }
            return state.waiters
        }
        for (id, _) in orphans {
            resolve(orphans[id]!, with: .failure(id: id, failure: .bridge(.disconnected)))
        }
        events.finish()
    }

    private func finish(_ id: Int, with frame: BridgeFrame) {
        guard let waiter = state.withLock({ $0.waiters.removeValue(forKey: id) }) else { return }
        resolve(waiter, with: frame)
    }

    private func resolve(_ waiter: Waiter, with frame: BridgeFrame) {
        switch (waiter, frame) {
        case (.call(let continuation), .result(_, let result)):
            continuation.resume(returning: result)
        case (.call(let continuation), .failure(_, let failure)):
            continuation.resume(throwing: failure.error)
        case (.stream(let continuation), .failure(_, .obd(.cancelled))):
            continuation.finish()
        case (.stream(let continuation), .failure(_, let failure)):
            continuation.finish(throwing: failure.error)
        case (.stream(let continuation), _):
            continuation.finish()
        case (.call(let continuation), _):
            continuation.resume(throwing: BridgeError.protocolMismatch("unerwarteter Rahmen"))
        }
    }
}
