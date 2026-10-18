import AdapterKit
import Foundation
import OBDCore

/// Service 09 results of one ECU.
public struct OBDECUInfo: Sendable, Codable, Equatable {
    public var ecu: String
    public var supportedInfoTypes: [UInt8]
    public var vin: String?
    public var calibrationIDs: [String]
    public var calibrationVerificationNumbers: [String]
    public var ecuName: String?
    public var issues: [String]

    public init(ecu: String, supportedInfoTypes: [UInt8] = [], vin: String? = nil, calibrationIDs: [String] = [],
                calibrationVerificationNumbers: [String] = [], ecuName: String? = nil, issues: [String] = []) {
        self.ecu = ecu
        self.supportedInfoTypes = supportedInfoTypes
        self.vin = vin
        self.calibrationIDs = calibrationIDs
        self.calibrationVerificationNumbers = calibrationVerificationNumbers
        self.ecuName = ecuName
        self.issues = issues
    }
}

/// SAE J1979 reads over the functional address 0x7DF. OBD lives on HS-CAN, the caller selects the bus.
public struct OBDService: Sendable {
    let driver: AdapterDriver
    let now: @Sendable () -> Date

    public init(driver: AdapterDriver, now: @escaping @Sendable () -> Date = { Date() }) {
        self.driver = driver
        self.now = now
    }

    /// Supported service 01 PIDs per responding ECU. The support query PIDs themselves are removed.
    public func supportedPIDs() async throws -> [UInt32: Set<UInt8>] {
        try await supportChain(service: 0x01, frame: nil)
    }

    public func readPID(_ pid: UInt8) async throws -> [MeasurementRecord] {
        try await readPIDBySource(pid).map(\.measurement)
    }

    /// Reads every supported PID once. Readiness and the freeze frame trigger are read by their own steps.
    public func readSnapshot(supported: [UInt32: Set<UInt8>]) async throws -> [UInt32: [MeasurementRecord]] {
        let skipped: Set<UInt8> = [0x01, 0x02, 0x41]
        var result: [UInt32: [MeasurementRecord]] = [:]
        for pid in Set(supported.values.flatMap { $0 }).subtracting(skipped).sorted() {
            for (source, measurement) in try await readPIDBySource(pid) where supported[source]?.contains(pid) == true {
                result[source, default: []].append(measurement)
            }
        }
        return result
    }

    public func readReadiness(pid: UInt8 = 0x01) async throws -> [UInt32: ReadinessReport] {
        let answer = try await driver.request([0x01, pid], to: .functional)
        var result: [UInt32: ReadinessReport] = [:]
        for message in answer.messages where message.payload.count >= 6 && message.payload[0] == 0x41 && message.payload[1] == pid {
            result[message.source.value] = try ReadinessReport.decode(Array(message.payload[2..<6]), kind: pid == 0x01 ? .sinceClear : .thisDriveCycle)
        }
        return result
    }

    /// Service 03 (stored), 07 (pending) or 0A (permanent).
    public func readTroubleCodes(service: UInt8) async throws -> [UInt32: [DTCCode]] {
        let answer = try await driver.request([service], to: .functional)
        var result: [UInt32: [DTCCode]] = [:]
        for message in answer.messages where message.payload.first == service &+ 0x40 {
            result[message.source.value] = try OBDTroubleCodes.decode(message.payload, service: service)
        }
        return result
    }

    /// Service 09. `full: false` reads only the VIN.
    public func readVehicleInfo(full: Bool) async throws -> [UInt32: OBDECUInfo] {
        var infos: [UInt32: OBDECUInfo] = [:]
        let support = try await driver.request([0x09, 0x00], to: .functional)
        for message in support.messages where message.payload.count >= 6 && message.payload[0] == 0x49 && message.payload[1] == 0x00 {
            let types = (try? OBDVehicleInfo.supportedInfoTypes(Array(message.payload[2..<6]))) ?? []
            infos[message.source.value] = OBDECUInfo(ecu: message.source.description, supportedInfoTypes: types.sorted())
        }
        let wanted: [UInt8] = full ? [0x02, 0x04, 0x06, 0x0A] : [0x02]
        for type in wanted where infos.values.contains(where: { $0.supportedInfoTypes.contains(type) }) {
            let answer = try await driver.request([0x09, type], to: .functional, timeout: .milliseconds(500))
            for message in answer.messages where message.payload.count >= 2 && message.payload[0] == 0x49 && message.payload[1] == type {
                let data = Array(message.payload.dropFirst(2))
                var info = infos[message.source.value] ?? OBDECUInfo(ecu: message.source.description)
                do {
                    switch type {
                    case 0x02: info.vin = try OBDVehicleInfo.decodeVIN(data)
                    case 0x04: info.calibrationIDs = try OBDVehicleInfo.decodeCalibrationIDs(data)
                    case 0x06: info.calibrationVerificationNumbers = try OBDVehicleInfo.decodeCVNs(data)
                    default: info.ecuName = try OBDVehicleInfo.decodeECUName(data)
                    }
                } catch let error as OBDError {
                    info.issues.append("Infotyp \(Hex.byteString(type)): \(error.message)")
                }
                infos[message.source.value] = info
            }
        }
        return infos
    }

    /// Service 02, frame 0: support chain first, then every supported and known PID.
    public func readFreezeFrame() async throws -> [UInt32: [MeasurementRecord]] {
        let support = try await supportChain(service: 0x02, frame: 0x00)
        var result: [UInt32: [MeasurementRecord]] = [:]
        for pid in Set(support.values.flatMap { $0 }).sorted() where J1979.definition(pid) != nil {
            let request: [UInt8] = [0x02, pid, 0x00]
            let answer = try await driver.request(request, to: .functional)
            for message in answer.messages {
                let payload = message.payload
                guard payload.count >= 3, payload[0] == 0x42, payload[1] == pid, support[message.source.value]?.contains(pid) == true else { continue }
                result[message.source.value, default: []].append(
                    measurement(service: 0x02, pid: pid, data: Array(payload.dropFirst(3)), source: message.source, request: request, response: payload))
            }
        }
        return result
    }

    // MARK: - Internals

    func readPIDBySource(_ pid: UInt8) async throws -> [(source: UInt32, measurement: MeasurementRecord)] {
        let request: [UInt8] = [0x01, pid]
        let answer = try await driver.request(request, to: .functional)
        return answer.messages.compactMap { message in
            let payload = message.payload
            guard payload.count >= 2, payload[0] == 0x41, payload[1] == pid else { return nil }
            return (message.source.value, measurement(service: 0x01, pid: pid, data: Array(payload.dropFirst(2)),
                                                      source: message.source, request: request, response: payload))
        }
    }

    /// Follows the support bitmasks 00, 20, 40, ... as long as the "next range supported" bit is set.
    func supportChain(service: UInt8, frame: UInt8?) async throws -> [UInt32: Set<UInt8>] {
        var result: [UInt32: Set<UInt8>] = [:]
        var base: UInt8 = 0x00
        while true {
            var request: [UInt8] = [service, base]
            if let frame { request.append(frame) }
            let answer = try await driver.request(request, to: .functional)
            let header = request.count
            var continueChain = false
            for message in answer.messages {
                let payload = message.payload
                guard payload.count >= header + 4, payload[0] == service &+ 0x40, payload[1] == base,
                      frame == nil || payload[2] == frame else { continue }
                let pids = try J1979.supportedPIDs(base: base, mask: Array(payload[header..<(header + 4)]))
                result[message.source.value, default: []].formUnion(pids.filter { !J1979.isSupportQuery($0) })
                if pids.contains(base &+ 0x20) { continueChain = true }
            }
            guard continueChain, base < 0xC0 else { break }
            base += 0x20
        }
        return result
    }

    func measurement(service: UInt8, pid: UInt8, data: [UInt8], source: CANIdentifier, request: [UInt8], response: [UInt8]) -> MeasurementRecord {
        let definition = J1979.definition(pid)
        let name = definition?.name ?? "PID \(Hex.byteString(pid))"
        let fields: [DecodedField]
        let confidence: Confidence
        do {
            fields = try J1979.decode(pid: pid, data: data)
            confidence = definition == nil ? .unknown : .standard
        } catch {
            fields = [DecodedField(label: name, value: .raw(data))]
            confidence = .unknown
        }
        return MeasurementRecord(
            id: "\(source):\(Hex.byteString(service)):\(Hex.byteString(pid))",
            name: name,
            fields: fields,
            rawHex: Hex.encode(data),
            provenance: Provenance(ecu: source.description, bus: .hsCAN, requestHex: Hex.encode(request),
                                   responseHex: Hex.encode(response), timestamp: now()),
            definition: DefinitionReference(
                reference: "SAE J1979 Dienst \(Hex.byteString(service)), PID \(Hex.byteString(pid))",
                formula: definition?.formula ?? "keine Definition, Rohwert",
                confidence: confidence)
        )
    }
}
