import Foundation
import Testing
@testable import DiagnosticEngine
import OBDCore
@testable import OpenOBDAppCore

@MainActor
@Suite struct AppModelTests {
    func makeModel(_ profile: String = "mondeo-mk4") async -> (AppModel, ReportStore) {
        let store = ReportStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("openobd-app-\(UUID().uuidString)"))
        let model = AppModel(store: store, discover: { [] })
        await model.select(.simulator(profile))
        return (model, store)
    }

    func waitFor(_ condition: @MainActor () -> Bool, timeout: Duration = .seconds(3)) async throws {
        let deadline = ContinuousClock.now + timeout
        while !condition() {
            guard ContinuousClock.now < deadline else { Issue.record("Bedingung nicht erreicht"); return }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    @Test func connectsToTheSimulator() async {
        let (model, _) = await makeModel()
        await model.connect()
        #expect(model.phase == .connected)
        #expect(model.adapter?.identity.device == "OBDLink EX (Simulator)")
        #expect(model.statusLine.contains("OBDLink EX (Simulator)"))
    }

    @Test func scanFillsReportProgressAndArchive() async throws {
        let (model, store) = await makeModel()
        await model.scan()
        #expect(model.phase == .connected)
        #expect(model.report?.modules.count == 8)
        try await waitFor { model.foundModules.count == 8 }
        try await waitFor { model.steps.allSatisfy { $0.state != .pending && $0.state != .running } }
        #expect(model.steps.map(\.step) == ScanStep.allCases.filter { $0.isIncluded(in: .standard) })
        #expect(!model.traffic.isEmpty)
        #expect(model.archive.count == 1)
        #expect(store.list().first?.simulated == true)
        #expect(model.report?.worstSeverity == .high)
        #expect(model.report?.primaryReadiness?.ignition == .compression)
    }

    @Test func silentVehicleIsNotAnAllClear() async throws {
        let (model, _) = await makeModel()
        await model.scan()
        var report = try #require(model.report)
        #expect(report.vehicleAnswered)

        report.findings = [
            Finding(kind: .noVehicleResponse, severity: .high, text: "Das Fahrzeug antwortet nicht.", evidence: ""),
            Finding(kind: .noVehiclePower, severity: .high, text: "Der Adapter bekommt keinen Strom vom Auto (0 V).", evidence: ""),
        ]
        #expect(!report.vehicleAnswered)
        #expect(report.silenceReason == "Der Adapter bekommt keinen Strom vom Auto (0 V).")
    }

    @Test func liveDataBuildsSeries() async throws {
        let (model, _) = await makeModel()
        model.livePIDs = [0x0C, 0x05]
        model.liveInterval = 20
        await model.startLive()
        #expect(model.phase == .live)
        try await waitFor { model.liveSeries.count == 2 && model.liveSeries.allSatisfy { $0.points.count >= 3 } }
        model.stopLive()
        #expect(model.phase == .connected)
        #expect(model.liveSeries.first?.name == "Motordrehzahl")
        #expect(model.liveSeries.first?.unit == "1/min")
    }

    @Test func pausingKeepsHistoryAndChangingValuesRestarts() async throws {
        let (model, _) = await makeModel()
        model.livePIDs = [0x0C, 0x05]
        model.liveInterval = 20
        await model.toggleLive()
        try await waitFor { model.liveSeries.count == 2 && model.liveSeries.allSatisfy { $0.points.count >= 2 } }
        await model.toggleLive()
        #expect(model.phase == .connected)
        let kept = model.liveSeries.first { $0.pid == 0x0C }?.points.count ?? 0
        #expect(kept >= 2)
        #expect(model.lastLiveUpdate != nil)

        await model.toggleLive()
        try await waitFor { (model.liveSeries.first { $0.pid == 0x0C }?.points.count ?? 0) > kept }
        await model.setLivePIDs([0x0C])
        #expect(model.phase == .live)
        #expect(model.liveSeries.map(\.pid) == [0x0C])
        model.stopLive()
        model.clearLive()
        #expect(model.liveSeries.isEmpty)
    }

    @Test func rawRequestsRespectThePolicy() async {
        let (model, _) = await makeModel()
        let read = await model.raw("22 F1 90", module: "7E0", bus: .hsCAN, functional: false)
        #expect(read.error == nil)
        #expect(read.lines.first?.hasPrefix("7E8") == true)
        let write = await model.raw("2E F1 90 00", module: "7E0", bus: .hsCAN, functional: false)
        #expect(write.error?.contains("nur lesende") == true)
        let badModule = await model.raw("22 F1 90", module: "XYZ", bus: .hsCAN, functional: false)
        #expect(badModule.error == "Ungültige Moduladresse. Erwartet drei Hex-Ziffern wie 7E0.")
    }

    @Test func failuresAreShownWithAHint() async {
        let store = ReportStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("openobd-app-\(UUID().uuidString)"))
        let model = AppModel(store: store, factory: { _ in throw OBDError.adapterNotFound }, discover: { [] })
        await model.connect()
        guard case .failed(let message) = model.phase else {
            Issue.record("Fehlerzustand erwartet")
            return
        }
        #expect(message.hasPrefix("Kein OBD-Adapter gefunden."))
        #expect(message.contains("OBDLink EX"))
    }

    @Test func archivedReportsCanBeOpened() async {
        let (model, store) = await makeModel("focus-mk4")
        await model.scan()
        let second = AppModel(store: store, discover: { [] })
        second.refreshArchive()
        guard let entry = second.archive.first else {
            Issue.record("Archiv ist leer")
            return
        }
        second.open(entry)
        #expect(second.report?.vehicle.vin == "WF0NXXGCHNSM67890")
        #expect(second.reportSource == .archive)
    }

    @Test func switchingConnectionDisconnects() async {
        let (model, _) = await makeModel()
        await model.connect()
        await model.select(.simulator("focus-mk4"))
        #expect(model.adapter == nil)
        #expect(model.phase == .idle)
        await model.connect()
        #expect(model.adapter?.link == "simulator:focus-mk4")
    }

    @Test func liveSeriesKeepsABoundedHistory() {
        var series = LiveSeries(pid: 0x0C, ecu: "7E8", name: "Motordrehzahl")
        let total = LiveSeries.capacity + 60
        for index in 0..<total {
            series.append(MeasurementRecord(
                id: "7E8:01:0C", name: "Motordrehzahl",
                fields: [DecodedField(label: "Motordrehzahl", value: .number(Double(800 + index), unit: "1/min"))],
                rawHex: "", provenance: Provenance(ecu: "7E8", bus: .hsCAN, requestHex: "010C", responseHex: "", timestamp: Date()),
                definition: DefinitionReference(reference: "", formula: "", confidence: .standard)))
        }
        #expect(series.points.count == LiveSeries.capacity)
        #expect(series.minimum == 800)
        #expect(series.maximum == Double(800 + total - 1))
        #expect(series.latestValue == Double(800 + total - 1))
        #expect(series.sampleCount == total)
        #expect(GaugeRange.forPID(0x0C)?.fraction(3000) == 0.5)
        #expect(series.range == GaugeRange.forPID(0x0C))
    }
}
