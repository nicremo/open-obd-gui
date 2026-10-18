import Darwin
import Foundation
import OBDCore
import Synchronization

/// Runs agent requests on behalf of the bridge. The app implements it on top of its model.
public protocol BridgeHandler: Sendable {
    func hello() async -> BridgeHello
    /// Runs one operation. `events` and `records` reach the calling agent while the operation runs.
    func perform(_ operation: BridgeOperation, events: @escaping @Sendable (EngineEvent) -> Void,
                 records: @escaping @Sendable (MeasurementRecord) -> Void) async throws -> BridgeResult
}

/// Listens on the bridge socket and serves every connection of the same user.
public final class BridgeServer: Sendable {
    public let path: String
    private let listener: Int32
    private let handler: any BridgeHandler
    private let running = Atomic(true)
    private let connections = Mutex<[Int: LineChannel]>([:])

    private init(path: String, listener: Int32, handler: any BridgeHandler) {
        self.path = path
        self.listener = listener
        self.handler = handler
    }

    public static func start(at path: String = BridgeEndpoint.defaultPath, handler: some BridgeHandler) throws -> BridgeServer {
        let listener = try BridgeSocket.listen(at: path)
        let server = BridgeServer(path: path, listener: listener, handler: handler)
        let thread = Thread { server.acceptLoop() }
        thread.name = "openobd.bridge.accept"
        thread.start()
        return server
    }

    /// Stops accepting, drops every connection (their running work is cancelled) and removes the socket file.
    public func stop() {
        guard running.exchange(false, ordering: .acquiringAndReleasing) else { return }
        unlink(path)
        let open = connections.withLock { Array($0.values) }
        open.forEach { $0.close() }
    }

    private func acceptLoop() {
        var counter = 0
        while running.load(ordering: .acquiring) {
            switch BridgeSocket.accept(listener, timeoutMilliseconds: 100) {
            case .timeout:
                continue
            case .failed:
                if running.load(ordering: .acquiring) { usleep(50_000) }
            case .client(let fd):
                guard BridgeSocket.peerIsCurrentUser(fd) else {
                    Darwin.close(fd)
                    continue
                }
                counter += 1
                let id = counter
                let channel = LineChannel(fd: fd)
                connections.withLock { $0[id] = channel }
                if !running.load(ordering: .acquiring) { channel.close() }
                Task {
                    await self.serve(channel)
                    self.connections.withLock { $0[id] = nil }
                }
            }
        }
        Darwin.close(listener)
    }

    private func serve(_ channel: LineChannel) async {
        let tasks = CallTable()
        for await line in channel.incoming {
            guard let command = try? BridgeCoding.decode(BridgeCommand.self, from: line) else {
                send(.failure(id: 0, failure: .bridge(.protocolMismatch("unlesbare Anfrage"))), on: channel)
                continue
            }
            switch command {
            case .cancel(let id):
                tasks.cancel(id)
            case .call(let id, let operation):
                let task = Task {
                    let frame: BridgeFrame
                    do {
                        frame = .result(id: id, result: try await self.run(operation, id: id, channel: channel))
                    } catch {
                        frame = .failure(id: id, failure: BridgeFailure(error))
                    }
                    self.send(frame, on: channel)
                    tasks.remove(id)
                }
                tasks.insert(task, for: id)
            }
        }
        // The client is gone: its work stops too.
        let pending = tasks.all()
        pending.forEach { $0.cancel() }
        for task in pending { await task.value }
        channel.close()
    }

    private func run(_ operation: BridgeOperation, id: Int, channel: LineChannel) async throws -> BridgeResult {
        if case .hello = operation {
            return .hello(await handler.hello())
        }
        return try await handler.perform(operation,
                                         events: { [self] in send(.event(id: id, event: $0), on: channel) },
                                         records: { [self] in send(.record(id: id, record: $0), on: channel) })
    }

    private func send(_ frame: BridgeFrame, on channel: LineChannel) {
        guard let line = try? BridgeCoding.line(frame) else { return }
        try? channel.send(line)
    }
}

/// Running calls of one connection, for cancellation.
private final class CallTable: Sendable {
    private let tasks = Mutex<[Int: Task<Void, Never>]>([:])

    func insert(_ task: Task<Void, Never>, for id: Int) {
        tasks.withLock { $0[id] = task }
    }

    func remove(_ id: Int) {
        _ = tasks.withLock { $0.removeValue(forKey: id) }
    }

    func cancel(_ id: Int) {
        tasks.withLock { $0[id] }?.cancel()
    }

    func all() -> [Task<Void, Never>] {
        tasks.withLock { Array($0.values) }
    }
}
