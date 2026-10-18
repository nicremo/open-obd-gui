import AdapterKit
import FordKnowledge
import Foundation
import OBDCore

/// The only public door to a vehicle. One operation at a time, progress and traffic on `events`.
public actor DiagnosticSession {
    public nonisolated let events: AsyncStream<EngineEvent>
    /// Synchronous listeners, called before the event reaches `events`.
    public nonisolated let observers = EventFanout()
    nonisolated let continuation: EventChannel
    let driver: AdapterDriver
    public nonisolated let knowledge: KnowledgeBase
    public nonisolated let linkLabel: String
    public nonisolated let simulated: Bool
    public nonisolated let vehicleTitle: String?
    public private(set) var vehicleHint: String?
    public private(set) var state: SessionState = .idle
    public private(set) var adapterSummary: AdapterSummary?
    public private(set) var lastReport: VehicleReport?
    var busy = false

    public init(link: any AdapterLink, knowledge: KnowledgeBase = .bundled, simulated: Bool = false,
                vehicleTitle: String? = nil, vehicleHint: String? = nil) {
        let (stream, sink) = AsyncStream.makeStream(of: EngineEvent.self, bufferingPolicy: .bufferingNewest(2_000))
        events = stream
        let continuation = EventChannel(stream: sink, observers: observers)
        self.continuation = continuation
        driver = AdapterDriver(link: link) { continuation.yield(.traffic($0)) }
        self.knowledge = knowledge
        linkLabel = link.label
        self.simulated = simulated
        self.vehicleTitle = vehicleTitle
        self.vehicleHint = vehicleHint
    }

    public func setVehicleHint(_ hint: String?) {
        vehicleHint = hint
    }

    @discardableResult
    public func connect() async throws -> AdapterSummary {
        try await exclusive("Verbinden") { try await connectAdapter() }
    }

    public func scan(depth: ScanDepth = .standard) async throws -> VehicleReport {
        try await exclusive("Auslesen") {
            try await ensureConnected()
            let pipeline = ScanPipeline(driver: driver, knowledge: knowledge, depth: depth, link: linkLabel, simulated: simulated,
                                        title: vehicleTitle, vehicleHint: vehicleHint, emit: { [continuation] in continuation.yield($0) })
            let report = try await pipeline.run()
            lastReport = report
            continuation.yield(.scanFinished(report.summary))
            return report
        }
    }

    public func discoverModules(buses: [BusKind] = [.hsCAN, .msCAN], sweep: Bool = false) async throws -> [DiscoveredModule] {
        try await exclusive("Modulsuche") {
            try await ensureConnected()
            let discovery = ModuleDiscovery(driver: driver, knowledge: knowledge)
            var modules: [DiscoveredModule] = []
            for bus in buses {
                guard await driver.isBusAvailable(bus) else { continue }
                do {
                    modules += try await discovery.discover(on: bus, sweep: sweep) { [continuation] in continuation.yield(.moduleFound($0)) }
                } catch OBDError.busUnavailable(let reason) where buses.count > 1 {
                    continuation.yield(.stepSkipped(.discoveryMS, reason: reason))
                }
            }
            return modules
        }
    }

    public func readModuleTroubleCodes(request: UInt32, bus: BusKind) async throws -> [ReportDTC] {
        try await exclusive("Fehlerspeicher lesen") {
            try await ensureConnected()
            try await driver.selectBus(bus)
            let (list, reply) = try await UDSService(driver: driver).readDTCs(from: request)
            switch reply.outcome {
            case .positive:
                return (list?.dtcs ?? []).map { DTCInterpreter.interpret($0, module: request, knowledge: knowledge) }
            case .negative(let code):
                throw OBDError.negativeResponse(service: 0x19, code: code)
            case .noResponse:
                throw OBDError.noData
            }
        }
    }

    public func readOBDTroubleCodes() async throws -> [ReportDTC] {
        try await exclusive("OBD-Fehlerspeicher lesen") {
            try await ensureConnected()
            try await driver.selectBus(.hsCAN)
            let obd = OBDService(driver: driver)
            let readiness = try await obd.readReadiness()
            var entries: [ReportDTC] = []
            for (service, source) in [(UInt8(0x03), ReportDTC.Source.obdStored), (0x07, .obdPending), (0x0A, .obdPermanent)] {
                for (ecu, codes) in try await obd.readTroubleCodes(service: service).sorted(by: { $0.key < $1.key }) {
                    entries += codes.map {
                        DTCInterpreter.interpret(obd: $0, source: source, ecu: ecu, milOn: readiness[ecu]?.milOn ?? false, knowledge: knowledge)
                    }
                }
            }
            return entries
        }
    }

    public func identify(request: UInt32, bus: BusKind, full: Bool = false) async throws -> IdentificationResult {
        try await exclusive("Identifizieren") {
            try await ensureConnected()
            try await driver.selectBus(bus)
            return try await Identification(uds: UDSService(driver: driver), knowledge: knowledge).read(module: request, full: full)
        }
    }

    public func readDID(_ did: UInt16, request: UInt32, bus: BusKind) async throws -> DIDReading {
        try await exclusive("Kennung lesen") {
            try await ensureConnected()
            try await driver.selectBus(bus)
            let reply = try await UDSService(driver: driver).readDID(did, from: request)
            return Identification.reading(did: did, reply: reply, knowledge: knowledge)
        }
    }

    public func supportedPIDs() async throws -> [UInt32: Set<UInt8>] {
        try await exclusive("PIDs abfragen") {
            try await ensureConnected()
            try await driver.selectBus(.hsCAN)
            return try await OBDService(driver: driver).supportedPIDs()
        }
    }

    public func readPIDs(_ pids: [UInt8]) async throws -> [MeasurementRecord] {
        try await exclusive("Messwerte lesen") {
            try await ensureConnected()
            try await driver.selectBus(.hsCAN)
            let obd = OBDService(driver: driver)
            var records: [MeasurementRecord] = []
            for pid in pids {
                records += try await obd.readPID(pid)
            }
            return records
        }
    }

    /// Expert request. Passes the same read-only policies as everything else.
    public func rawRequest(_ payload: [UInt8], target: RequestTarget, bus: BusKind, timeout: Duration = .milliseconds(500)) async throws -> RequestResult {
        try await exclusive("Rohanfrage") {
            try await ensureConnected()
            try await driver.selectBus(bus)
            return try await driver.request(payload, to: target, timeout: timeout)
        }
    }

    public func close() async {
        await driver.close()
        state = .closed
        adapterSummary = nil
        continuation.finish()
    }

    // MARK: - Internals

    func exclusive<T: Sendable>(_ label: String, _ body: () async throws -> T) async throws -> T {
        guard state != .closed else { throw OBDError.disconnected }
        guard !busy else { throw OBDError.busy }
        busy = true
        state = .working(label)
        defer {
            busy = false
            if state != .closed {
                state = adapterSummary == nil ? .idle : .connected
            }
        }
        do {
            return try await body()
        } catch let error as OBDError where ScanPipeline.isFatal(error) {
            adapterSummary = nil
            throw error
        }
    }

    func ensureConnected() async throws {
        if adapterSummary == nil {
            _ = try await connectAdapter()
        }
    }

    func connectAdapter() async throws -> AdapterSummary {
        do {
            let identity = try await driver.initialize()
            let summary = AdapterSummary(link: linkLabel, identity: identity, voltage: await driver.voltage,
                                         msCANAvailable: await driver.isBusAvailable(.msCAN), simulated: simulated)
            adapterSummary = summary
            return summary
        } catch {
            adapterSummary = nil
            throw error
        }
    }
}
