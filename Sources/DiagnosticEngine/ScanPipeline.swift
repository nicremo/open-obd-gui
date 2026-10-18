import AdapterKit
import FordKnowledge
import Foundation
import OBDCore

/// One scan from adapter check to report. Every step is fault tolerant. Only loss of the adapter and cancellation abort.
struct ScanPipeline: Sendable {
    let driver: AdapterDriver
    let knowledge: KnowledgeBase
    let depth: ScanDepth
    let link: String
    let simulated: Bool
    let title: String?
    let vehicleHint: String?
    let emit: @Sendable (EngineEvent) -> Void

    func run() async throws -> VehicleReport {
        let clock = ContinuousClock()
        let started = clock.now
        let builder = ReportBuilder(knowledge: knowledge, depth: depth, link: link, simulated: simulated, title: title, vehicleHint: vehicleHint)
        let obd = OBDService(driver: driver)
        let uds = UDSService(driver: driver)
        let discovery = ModuleDiscovery(driver: driver, knowledge: knowledge)
        let identification = Identification(uds: uds, knowledge: knowledge)
        var supported: [UInt32: Set<UInt8>] = [:]
        var readiness: [UInt32: ReadinessReport] = [:]
        var storedCodes = false
        var modules: [DiscoveredModule] = []
        var moduleCodes: [String: [UDSDTC]] = [:]

        func eachModule(_ work: (DiscoveredModule) async throws -> Void) async throws {
            for bus in BusKind.allCases {
                for module in modules where module.bus == bus {
                    do {
                        try await driver.selectBus(bus)
                        try await work(module)
                    } catch let error as OBDError where !Self.isFatal(error) {
                        builder.updateModule(module.id) { $0.issues.append(error.message) }
                    }
                }
            }
        }

        try await step(.adapter, builder) {
            builder.identity = await driver.identity
            builder.voltage = try await driver.readVoltage()
            let msCAN = await driver.isBusAvailable(.msCAN)
            builder.buses = [
                BusAvailability(bus: .hsCAN, available: true, note: nil),
                BusAvailability(bus: .msCAN, available: msCAN, note: msCAN ? nil : "Der Adapter kann nicht auf MS-CAN umschalten."),
            ]
            let voltage = builder.voltage.map { "\(MeasuredValue.format($0)) V" } ?? "Spannung unbekannt"
            return "\(builder.identity?.displayName ?? "Adapter"), \(voltage)"
        }

        try await step(.obdSupport, builder) {
            try await driver.selectBus(.hsCAN)
            supported = try await obd.supportedPIDs()
            for (ecu, pids) in supported {
                builder.updateECU(ecu) { $0.supportedPIDs = pids.sorted().map(Hex.byteString) }
            }
            guard !supported.isEmpty else {
                builder.warnings.append("Kein Steuergerät antwortet auf OBD-Anfragen. Ist die Zündung an?")
                return "keine OBD-Antwort"
            }
            builder.protocolName = "ISO 15765-4 CAN, 11 Bit, 500 kbit/s"
            return supported.keys.sorted().map { Hex.canID($0, extended: false) }.joined(separator: ", ")
        }

        try await step(.obdReadiness, builder) {
            guard supported.values.contains(where: { $0.contains(0x01) }) else { return "nicht unterstützt" }
            try await driver.selectBus(.hsCAN)
            readiness = try await obd.readReadiness(pid: 0x01)
            for (ecu, report) in readiness {
                builder.updateECU(ecu) { $0.readiness = report }
            }
            if depth != .quick, supported.values.contains(where: { $0.contains(0x41) }) {
                for (ecu, report) in try await obd.readReadiness(pid: 0x41) {
                    builder.updateECU(ecu) { $0.readinessThisCycle = report }
                }
            }
            let incomplete = readiness.values.flatMap(\.incompleteMonitors).count
            return incomplete == 0 ? "alle Tests abgeschlossen" : "nicht abgeschlossen: \(incomplete)"
        }

        try await step(.obdTroubleCodes, builder) {
            guard !supported.isEmpty else { return "keine OBD-Steuergeräte" }
            try await driver.selectBus(.hsCAN)
            var count = 0
            for (service, source) in [(UInt8(0x03), ReportDTC.Source.obdStored), (0x07, .obdPending), (0x0A, .obdPermanent)] {
                for (ecu, codes) in try await obd.readTroubleCodes(service: service) {
                    let entries = codes.map {
                        DTCInterpreter.interpret(obd: $0, source: source, ecu: ecu, milOn: readiness[ecu]?.milOn ?? false, knowledge: knowledge)
                    }
                    builder.updateECU(ecu) { $0.troubleCodes += entries }
                    entries.forEach { emit(.troubleCodeFound($0)) }
                    count += entries.count
                    if service == 0x03 && !codes.isEmpty { storedCodes = true }
                }
            }
            return count == 0 ? "keine Einträge" : "Einträge: \(count)"
        }

        try await step(.obdVehicleInfo, builder) {
            guard !supported.isEmpty else { return "keine OBD-Steuergeräte" }
            try await driver.selectBus(.hsCAN)
            let infos = try await obd.readVehicleInfo(full: depth != .quick)
            for (ecu, info) in infos {
                builder.updateECU(ecu) { $0.info = info }
            }
            return infos.values.compactMap(\.vin).first.map { "VIN \($0)" } ?? "keine VIN gemeldet"
        }

        try await step(.obdFreezeFrame, builder) {
            guard storedCodes else { return "kein gespeicherter Fehler, daher kein Freeze Frame" }
            try await driver.selectBus(.hsCAN)
            let frames = try await obd.readFreezeFrame()
            for (ecu, records) in frames {
                builder.updateECU(ecu) { $0.freezeFrame = records }
            }
            return "Werte: \(frames.values.map(\.count).reduce(0, +))"
        }

        try await step(.obdSnapshot, builder) {
            guard !supported.isEmpty else { return "keine OBD-Steuergeräte" }
            try await driver.selectBus(.hsCAN)
            let snapshot = try await obd.readSnapshot(supported: supported)
            for (ecu, records) in snapshot {
                builder.updateECU(ecu) { $0.snapshot = records }
            }
            return "Messwerte: \(snapshot.values.map(\.count).reduce(0, +))"
        }

        try await step(.discoveryHS, builder) {
            let found = try await discovery.discover(on: .hsCAN, sweep: depth == .deep) { emit(.moduleFound($0)) }
            modules += found
            found.forEach(builder.addModule)
            return found.isEmpty ? "keine Steuergeräte" : found.map { $0.catalogAcronym ?? $0.requestHex }.joined(separator: ", ")
        }

        try await step(.discoveryMS, builder) {
            guard await driver.isBusAvailable(.msCAN) else { return "MS-CAN nicht verfügbar" }
            do {
                let found = try await discovery.discover(on: .msCAN, sweep: depth == .deep) { emit(.moduleFound($0)) }
                modules += found
                found.forEach(builder.addModule)
                return found.isEmpty ? "keine Steuergeräte" : found.map { $0.catalogAcronym ?? $0.requestHex }.joined(separator: ", ")
            } catch OBDError.busUnavailable(let reason) {
                builder.buses = builder.buses.map { $0.bus == .msCAN ? BusAvailability(bus: .msCAN, available: false, note: reason) : $0 }
                return "MS-CAN nicht verfügbar: \(reason)"
            }
        }

        try await step(.identification, builder) {
            var count = 0
            try await eachModule { module in
                let result = try await identification.read(module: module.requestID, full: depth == .deep)
                builder.updateModule(module.id) {
                    $0.identification = result.readings
                    $0.unsupportedIdentifiers = result.unsupportedCount
                    $0.issues += result.issues
                }
                count += result.readings.count
            }
            return "Kennungen: \(count)"
        }

        try await step(.moduleTroubleCodes, builder) {
            var count = 0
            try await eachModule { module in
                let (list, reply) = try await uds.readDTCs(from: module.requestID)
                switch reply.outcome {
                case .positive:
                    let dtcs = list?.dtcs ?? []
                    moduleCodes[module.id] = dtcs
                    let entries = dtcs.map { DTCInterpreter.interpret($0, module: module.requestID, knowledge: knowledge) }
                    builder.updateModule(module.id) {
                        $0.troubleCodes = entries
                        $0.troubleCodeSupport = "UDS 19 02"
                    }
                    entries.forEach { emit(.troubleCodeFound($0)) }
                    count += entries.count
                case .negative(let code):
                    builder.updateModule(module.id) {
                        $0.troubleCodeSupport = "nicht unterstützt (NRC \(Hex.byteString(code)): \(NegativeResponseCode.german(code)))"
                    }
                case .noResponse:
                    builder.updateModule(module.id) { $0.issues.append("Keine Antwort auf das Lesen des Fehlerspeichers.") }
                }
            }
            return count == 0 ? "keine Einträge" : "Einträge: \(count)"
        }

        try await step(.troubleCodeDetails, builder) {
            var count = 0
            try await eachModule { module in
                for dtc in moduleCodes[module.id] ?? [] {
                    let snapshot = try await uds.readSnapshot(dtc, from: module.requestID)
                    let extended = try await uds.readExtendedData(dtc, from: module.requestID)
                    builder.updateModule(module.id) { report in
                        guard let index = report.troubleCodes.firstIndex(where: { $0.displayCode == dtc.displayCode }) else { return }
                        if case .positive(let data) = snapshot.outcome { report.troubleCodes[index].snapshotHex = Hex.encode(data) }
                        if case .positive(let data) = extended.outcome { report.troubleCodes[index].extendedDataHex = Hex.encode(data) }
                    }
                    count += 1
                }
            }
            return "vertieft: \(count)"
        }

        try await step(.asBuilt, builder) {
            var count = 0
            try await eachModule { module in
                let result = try await identification.readAsBuilt(module: module.requestID)
                builder.updateModule(module.id) {
                    $0.asBuilt = result.readings
                    $0.issues += result.issues
                }
                count += result.readings.count
            }
            return "Blöcke: \(count)"
        }

        return builder.build(duration: clock.now - started)
    }

    func step(_ step: ScanStep, _ builder: ReportBuilder, _ body: () async throws -> String) async throws {
        guard step.isIncluded(in: depth) else {
            let reason = "nicht Teil der Tiefe \(depth.german)"
            builder.record(step, .skipped, .zero, reason)
            emit(.stepSkipped(step, reason: reason))
            return
        }
        if Task.isCancelled { throw OBDError.cancelled }
        emit(.stepStarted(step))
        let started = ContinuousClock.now
        do {
            let summary = try await body()
            builder.record(step, .ok, ContinuousClock.now - started, summary)
            emit(.stepFinished(step, summary: summary))
        } catch let error as OBDError where Self.isFatal(error) {
            builder.record(step, .failed, ContinuousClock.now - started, error.message)
            emit(.stepFailed(step, message: error.message))
            throw error
        } catch {
            let message = (error as? OBDError)?.message ?? String(describing: error)
            builder.record(step, .failed, ContinuousClock.now - started, message)
            builder.warnings.append("\(step.title): \(message)")
            emit(.stepFailed(step, message: message))
        }
    }

    static func isFatal(_ error: OBDError) -> Bool {
        switch error {
        case .disconnected, .cancelled, .adapterNotResponding: true
        default: false
        }
    }
}
