import AdapterKit
import DiagnosticEngine
import Foundation
import Observation
import OBDCore
import VehicleSim

/// State of the app. All diagnostics run through one `DiagnosticSession`.
@MainActor
@Observable
public final class AppModel {
    public enum Phase: Equatable, Sendable {
        case idle
        case connecting
        case connected
        case scanning
        case live
        case failed(String)

        public var isBusy: Bool { self == .connecting || self == .scanning }
    }

    public typealias SessionFactory = @Sendable (ConnectionChoice) throws -> DiagnosticSession

    public var section: AppSection = .cockpit
    public private(set) var choice: ConnectionChoice = .automatic
    public var vehicleHint: String?
    public var depth: ScanDepth = .standard
    public internal(set) var phase: Phase = .idle
    public internal(set) var adapter: AdapterSummary?
    public private(set) var candidates: [SerialDeviceCandidate] = []
    public private(set) var steps: [StepProgress] = []
    public private(set) var foundModules: [DiscoveredModule] = []
    public private(set) var report: VehicleReport?
    public private(set) var reportSource: ReportSource = .none
    public private(set) var traffic: [TrafficLine] = []
    public private(set) var liveSeries: [LiveSeries] = []
    public var livePIDs: [UInt8] = [0x0C, 0x0D, 0x05, 0x04, 0x42, 0x0B]
    public var liveInterval = 300
    /// Visible time span of live charts in seconds.
    public var liveWindow: TimeInterval = 60
    public var selectedSeriesID: String?
    public private(set) var lastLiveUpdate: Date?
    public var inspected: InspectorItem?
    public var showInspector = false
    public private(set) var archive: [ReportStore.Entry] = []
    /// What an agent is reading through the bridge right now.
    public internal(set) var agentActivity: String?
    public internal(set) var agentBridge: AgentBridgeStatus = .off

    @ObservationIgnored let store: ReportStore
    @ObservationIgnored let factory: SessionFactory
    @ObservationIgnored let discover: @Sendable () -> [SerialDeviceCandidate]
    @ObservationIgnored var session: DiagnosticSession?
    @ObservationIgnored var bridgeServer: BridgeServer?
    @ObservationIgnored private var eventsTask: Task<Void, Never>?
    @ObservationIgnored private var liveTask: Task<Void, Never>?
    @ObservationIgnored private var trafficCounter = 0
    @ObservationIgnored private var liveGeneration = 0
    @ObservationIgnored private var pendingRecords: [MeasurementRecord] = []
    @ObservationIgnored private var flushScheduled = false
    static let liveRedrawInterval: Duration = .milliseconds(200)
    static let trafficLimit = 800

    public init(store: ReportStore = ReportStore(), factory: @escaping SessionFactory = AppModel.makeSession,
                discover: @escaping @Sendable () -> [SerialDeviceCandidate] = { DeviceDiscovery.candidates() }) {
        self.store = store
        self.factory = factory
        self.discover = discover
    }

    // MARK: - Derived state

    public var statusLine: String {
        switch phase {
        case .idle: return adapter == nil ? "Nicht verbunden" : "Verbunden"
        case .connecting: return "Verbinde mit dem Adapter"
        case .connected:
            guard let adapter else { return "Verbunden" }
            let voltage = adapter.voltage.map { " · \(MeasuredValue.format($0)) V" } ?? ""
            return "\(adapter.identity.displayName)\(voltage)"
        case .scanning: return "Lese das Fahrzeug aus"
        case .live: return "Live-Daten laufen"
        case .failed(let message): return message
        }
    }

    // MARK: - Actions

    public func refreshDevices() {
        candidates = discover()
    }

    public func refreshArchive() {
        archive = store.list()
    }

    /// Switching the connection closes the current session first.
    public func select(_ newChoice: ConnectionChoice) async {
        guard newChoice != choice else { return }
        await disconnect()
        choice = newChoice
        phase = .idle
    }

    public func connect() async {
        guard !isOccupied else { return }
        stopLive()
        phase = .connecting
        do {
            let session = try ensureSession()
            adapter = try await retryingBusy { try await session.connect() }
            phase = .connected
        } catch {
            await fail(error)
        }
    }

    public func scan() async {
        guard !isOccupied else { return }
        do {
            _ = try await runScan(depth: depth)
        } catch {
            await fail(error)
        }
    }

    /// The scan behind the button and behind an agent's request: step list, progress, report, archive.
    func runScan(depth: ScanDepth) async throws -> VehicleReport {
        stopLive()
        steps = ScanStep.allCases.filter { $0.isIncluded(in: depth) }.map { StepProgress(step: $0, state: .pending) }
        foundModules = []
        phase = .scanning
        let session = try ensureSession()
        await session.setVehicleHint(vehicleHint ?? choice.simulatorProfile)
        if adapter == nil {
            adapter = try await retryingBusy { try await session.connect() }
        }
        let report = try await retryingBusy { try await session.scan(depth: depth) }
        self.report = report
        reportSource = .scan
        _ = try? store.save(report)
        refreshArchive()
        phase = .connected
        return report
    }

    public func startLive() async {
        guard liveTask == nil, !isOccupied, !livePIDs.isEmpty else { return }
        if adapter == nil {
            await connect()
            guard adapter != nil else { return }
        }
        guard let session else { return }
        let pids = livePIDs
        let interval = liveInterval
        liveSeries.removeAll { !pids.contains($0.pid) }
        phase = .live
        liveGeneration += 1
        let generation = liveGeneration
        liveTask = Task { [weak self] in
            // A stream that was just stopped may still hold the session for a moment.
            var attempts = 0
            while !Task.isCancelled {
                do {
                    for try await record in session.live(pids: pids, interval: .milliseconds(interval)) {
                        self?.ingest(record)
                    }
                    break
                } catch OBDError.busy where attempts < 40 {
                    attempts += 1
                    try? await Task.sleep(for: .milliseconds(25))
                } catch {
                    self?.liveEnded(error, generation: generation)
                    return
                }
            }
            self?.liveEnded(nil, generation: generation)
        }
    }

    /// Pause keeps the connection and the collected history. Resuming continues the series with a visible gap.
    public func toggleLive() async {
        if phase == .live {
            stopLive()
        } else {
            await startLive()
        }
    }

    /// Changes the polled values. A running stream restarts with the new set.
    public func setLivePIDs(_ pids: [UInt8]) async {
        livePIDs = pids
        liveSeries.removeAll { !pids.contains($0.pid) }
        guard phase == .live else { return }
        stopLive()
        await startLive()
    }

    public func clearLive() {
        pendingRecords = []
        liveSeries = []
        lastLiveUpdate = nil
    }

    public func stopLive() {
        liveTask?.cancel()
        liveTask = nil
        liveGeneration += 1
        if phase == .live {
            phase = adapter == nil ? .idle : .connected
        }
    }

    public func raw(_ text: String, module: String, bus: BusKind, functional: Bool) async -> RawOutcome {
        do {
            let bytes = try Hex.decode(text)
            try ReadOnlyPolicy.validate(bytes)
            let target: RequestTarget
            if functional {
                target = .functional
            } else {
                guard module.count == 3, let id = Hex.parseCANID(module.uppercased()), (0x700...0x7FF).contains(id) else {
                    return RawOutcome(request: text, lines: [], error: "Ungültige Moduladresse. Erwartet drei Hex-Ziffern wie 7E0.")
                }
                target = .module(id)
            }
            let session = try ensureSession()
            let result = try await retryingBusy { try await session.rawRequest(bytes, target: target, bus: bus) }
            let lines = result.messages.map { "\($0.source)  \(Hex.encode($0.payload, separator: " "))" }
            return RawOutcome(request: Hex.encode(bytes, separator: " "), lines: lines.isEmpty ? ["keine Antwort"] : lines, error: nil)
        } catch {
            return RawOutcome(request: text, lines: [], error: (error as? OBDError)?.message ?? String(describing: error))
        }
    }

    public func disconnect() async {
        stopLive()
        await closeSession()
        if case .failed = phase { return }
        phase = .idle
    }

    public func open(_ entry: ReportStore.Entry) {
        guard let loaded = try? store.load(entry.url) else { return }
        report = loaded
        reportSource = .archive
        section = .cockpit
    }

    public func inspect(_ item: InspectorItem) {
        inspected = item
        showInspector = true
    }

    // MARK: - Session plumbing

    nonisolated public static func makeSession(_ choice: ConnectionChoice) throws -> DiagnosticSession {
        switch choice {
        case .simulator(let id):
            guard let profile = VehicleProfile.named(id) else { throw OBDError.adapterNotFound }
            return DiagnosticSession(link: SimulatedLink(profile: profile), simulated: true, vehicleTitle: profile.title, vehicleHint: id)
        case .port(let path):
            return DiagnosticSession(link: try SerialLink.open(path: path))
        case .automatic:
            guard let best = DeviceDiscovery.candidates().first(where: \.isLikelyOBDAdapter) else { throw OBDError.adapterNotFound }
            return DiagnosticSession(link: try SerialLink.open(path: best.path))
        }
    }

    func ensureSession() throws -> DiagnosticSession {
        if let session { return session }
        let created = try factory(choice)
        session = created
        eventsTask = Task { [weak self] in
            for await event in created.events {
                self?.handle(event)
            }
        }
        return created
    }

    func closeSession() async {
        eventsTask?.cancel()
        eventsTask = nil
        if let session {
            await session.close()
        }
        session = nil
        adapter = nil
    }

    /// A live stream that was just stopped may still hold the session for a moment.
    func retryingBusy<T: Sendable>(_ operation: () async throws -> T) async throws -> T {
        for _ in 0..<40 {
            do {
                return try await operation()
            } catch OBDError.busy {
                try await Task.sleep(for: .milliseconds(25))
            }
        }
        return try await operation()
    }

    func fail(_ error: any Error) async {
        guard let obd = error as? OBDError else {
            phase = .failed(String(describing: error))
            return
        }
        phase = .failed([obd.message, obd.hint].compactMap { $0 }.joined(separator: " "))
        switch obd {
        case .adapterNotFound, .portBusy, .portOpenFailed, .disconnected, .adapterNotResponding:
            let message = phase
            await closeSession()
            phase = message
        default:
            break
        }
    }

    func handle(_ event: EngineEvent) {
        switch event {
        case .stepStarted(let step): update(step, .running)
        case .stepFinished(let step, let summary): update(step, .done(summary))
        case .stepSkipped(let step, let reason): update(step, .skipped(reason))
        case .stepFailed(let step, let message): update(step, .failed(message))
        case .moduleFound(let module):
            if !foundModules.contains(module) { foundModules.append(module) }
        case .traffic(let event):
            trafficCounter += 1
            traffic.append(TrafficLine(id: trafficCounter, direction: event.direction, text: event.text, time: event.timestamp))
            if traffic.count > Self.trafficLimit {
                traffic.removeFirst(traffic.count - Self.trafficLimit)
            }
        case .troubleCodeFound, .scanFinished:
            break
        }
    }

    func update(_ step: ScanStep, _ state: StepState) {
        if let index = steps.firstIndex(where: { $0.step == step }) {
            steps[index].state = state
        }
    }

    /// Collects records and publishes them at most every `liveRedrawInterval`.
    func ingest(_ record: MeasurementRecord) {
        pendingRecords.append(record)
        guard !flushScheduled else { return }
        flushScheduled = true
        Task { [weak self] in
            try? await Task.sleep(for: Self.liveRedrawInterval)
            self?.flushLive()
        }
    }

    func flushLive() {
        flushScheduled = false
        let records = pendingRecords
        pendingRecords = []
        guard !records.isEmpty else { return }
        var updated = liveSeries
        for record in records {
            let pid = UInt8(record.id.suffix(2), radix: 16) ?? 0
            guard livePIDs.contains(pid) else { continue }
            let key = "\(record.provenance.ecu):\(Hex.byteString(pid))"
            if let index = updated.firstIndex(where: { $0.id == key }) {
                updated[index].append(record)
            } else {
                var series = LiveSeries(pid: pid, ecu: record.provenance.ecu, name: record.name)
                series.append(record)
                updated.append(series)
            }
        }
        liveSeries = updated
        lastLiveUpdate = records.last?.provenance.timestamp
    }

    /// Ignores the end of a stream that was already replaced by a newer one.
    func liveEnded(_ error: (any Error)?, generation: Int) {
        guard generation == liveGeneration else { return }
        liveTask = nil
        if let error, !(error is CancellationError), (error as? OBDError) != .cancelled {
            Task { await fail(error) }
            return
        }
        if phase == .live {
            phase = adapter == nil ? .idle : .connected
        }
    }
}
