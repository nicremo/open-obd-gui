import AdapterKit
import FordKnowledge
import Foundation
import OBDCore

/// Everything a front end can ask of a vehicle. Implemented by `DiagnosticSession` (adapter, simulator, capture)
/// and by `BridgeClient` (the session of the running app). CLI and MCP only talk to this protocol.
public protocol DiagnosticBackend: Sendable {
    /// Where the data comes from, for example `/dev/cu.usbserial-A1`, `simulator:mondeo-mk4` or `app:simulator:mondeo-mk4`.
    var linkLabel: String { get }
    var knowledge: KnowledgeBase { get }
    /// Progress and traffic. Has a single consumer.
    var events: AsyncStream<EngineEvent> { get }

    func connect() async throws -> AdapterSummary
    func scan(depth: ScanDepth) async throws -> VehicleReport
    func discoverModules(buses: [BusKind], sweep: Bool) async throws -> [DiscoveredModule]
    func readModuleTroubleCodes(request: UInt32, bus: BusKind) async throws -> [ReportDTC]
    func readOBDTroubleCodes() async throws -> [ReportDTC]
    func identify(request: UInt32, bus: BusKind, full: Bool) async throws -> IdentificationResult
    func readDID(_ did: UInt16, request: UInt32, bus: BusKind) async throws -> DIDReading
    func supportedPIDs() async throws -> [UInt32: Set<UInt8>]
    func readPIDs(_ pids: [UInt8]) async throws -> [MeasurementRecord]
    /// Expert request. Passes the same read-only policies as everything else.
    func rawRequest(_ payload: [UInt8], target: RequestTarget, bus: BusKind, timeout: Duration) async throws -> RequestResult
    func live(pids: [UInt8], interval: Duration) -> AsyncThrowingStream<MeasurementRecord, any Error>
    /// Releases this front end's hold. For the bridge it closes the socket, not the app's session.
    func close() async
}

extension DiagnosticSession: DiagnosticBackend {}
