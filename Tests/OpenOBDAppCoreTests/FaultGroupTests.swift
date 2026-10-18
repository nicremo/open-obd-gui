import Foundation
import Testing
@testable import DiagnosticEngine
import OBDCore
@testable import OpenOBDAppCore

@MainActor
@Suite struct FaultGroupTests {
    @Test func obdAndUDSEntriesOfOneModuleBecomeOneFault() async throws {
        let store = ReportStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("openobd-fg-\(UUID().uuidString)"))
        let model = AppModel(store: store, discover: { [] })
        await model.select(.simulator("mondeo-mk4"))
        await model.scan()
        let report = try #require(model.report)
        let groups = FaultGroup.groups(from: report)

        #expect(groups.count == report.summary.faultCount)
        let pcm = try #require(groups.first { $0.code == "P0401" })
        #expect(pcm.module == "7E0")
        #expect(pcm.entries.count >= 2)
        #expect(pcm.sources.contains(.uds))
        #expect(pcm.sources.contains(.obdStored))
        #expect(pcm.primary.source == .uds)
    }

    @Test func groupsAreSortedBySeverityThenActivity() {
        func dtc(_ module: String, _ code: String, _ severity: Severity, _ state: String, _ source: ReportDTC.Source = .uds) -> ReportDTC {
            ReportDTC(id: "\(module)-\(code)-\(source.rawValue)", module: module, code: code, failureType: nil, displayCode: code,
                      source: source, statusByte: nil, statusLabels: [], state: state, system: "", origin: "", subsystem: nil,
                      failureTypeCategory: nil, failureTypeDetail: nil, title: nil, titleSource: nil, titleConfidence: nil,
                      explanation: nil, severity: severity, severityReasons: [], snapshotHex: nil, extendedDataHex: nil)
        }
        let groups = FaultGroup.groups(from: [
            dtc("760", "C0001", .medium, "gespeichert"),
            dtc("7E0", "P0001", .high, "gespeichert"),
            dtc("720", "B0001", .medium, "aktiv"),
            dtc("7E0", "P0001", .medium, "gespeichert", .obdStored),
        ])
        #expect(groups.map(\.code) == ["P0001", "B0001", "C0001"])
        #expect(groups[0].entries.count == 2)
        #expect(groups[0].primary.source == .uds)
    }
}

@Suite struct ValueDisplayTests {
    func record(_ id: String, _ value: Double, unit: String, time: Date = Date()) -> MeasurementRecord {
        MeasurementRecord(id: id, name: "Test", fields: [DecodedField(label: "Test", value: .number(value, unit: unit))], rawHex: "",
                          provenance: Provenance(ecu: "7E8", bus: .hsCAN, requestHex: "01 0C", responseHex: "", timestamp: time),
                          definition: DefinitionReference(reference: "", formula: "", confidence: .standard))
    }

    @Test func recordsUseFixedDecimalsOfTheirPID() {
        #expect(record("7E8:01:0C", 850.25, unit: "1/min").displayNumber == "850")
        #expect(record("7E8:01:42", 12.6, unit: "V").displayNumber == "12,60")
        #expect(record("7E8:01:42", 12.6, unit: "V").displayUnit == "V")
        #expect(record("7E8:01:42", 12.6, unit: "V").pid == 0x42)
        #expect(record("7E0:22:F190", 1, unit: "").pid == nil)
    }

    @Test func seriesKeepsMeanOverAllSamplesAndSplitsGaps() {
        var series = LiveSeries(pid: 0x0C, ecu: "7E8", name: "Motordrehzahl")
        let start = Date(timeIntervalSince1970: 1000)
        for (offset, value) in [(0.0, 800.0), (0.3, 900.0), (0.6, 1000.0), (5.0, 1100.0)] {
            series.append(record("7E8:01:0C", value, unit: "1/min", time: start.addingTimeInterval(offset)))
        }
        #expect(series.mean == 950)
        #expect(series.segments(maximumGap: 1).map(\.count) == [3, 1])
        #expect(series.format(950.4) == "950")
    }
}
