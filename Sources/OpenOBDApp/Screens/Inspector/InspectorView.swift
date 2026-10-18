import DiagnosticEngine
import FordKnowledge
import OBDCore
import OpenOBDAppCore
import SwiftUI

enum InspectorTab: String, CaseIterable, Identifiable {
    case explained, raw, definition, statistics, json

    var id: String { rawValue }

    var title: String {
        switch self {
        case .explained: "Erklärt"
        case .raw: "Rohdaten"
        case .definition: "Definition"
        case .statistics: "Statistik"
        case .json: "JSON"
        }
    }
}

/// Same structure for every item. Head with kind, title, main value and confidence,
/// then tabs in a fixed order. Missing tabs are hidden.
struct InspectorView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("inspector.tab") private var tabRaw = InspectorTab.explained.rawValue

    var body: some View {
        if let item = model.inspected {
            let content = InspectorContent(item: item, liveSeries: liveSeries(for: item), report: model.report)
            let tabs = content.tabs
            let tab = tabs.first { $0.rawValue == tabRaw } ?? .explained
            VStack(alignment: .leading, spacing: 0) {
                content.header
                    .padding(Spacing.l)
                Picker("Ansicht", selection: Binding(get: { tab }, set: { tabRaw = $0.rawValue })) {
                    ForEach(tabs) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, Spacing.l)
                .padding(.bottom, Spacing.m)
                Divider()
                ScrollView {
                    content.body(for: tab)
                        .padding(Spacing.l)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .background(Palette.background)
        } else {
            EmptyState(symbol: "sidebar.trailing", title: "Technik", message: "Wähle einen Fehlercode, Messwert, ein Steuergerät oder eine Kennung, um alle Rohdaten zu sehen.")
                .frame(maxHeight: .infinity)
                .background(Palette.background)
        }
    }

    private func liveSeries(for item: InspectorItem) -> LiveSeries? {
        guard case .measurement(let record) = item else { return nil }
        return model.liveSeries.first { $0.latest?.id == record.id && $0.ecu == record.provenance.ecu }
    }
}

@MainActor
struct InspectorContent {
    let item: InspectorItem
    let liveSeries: LiveSeries?
    let report: VehicleReport?

    var tabs: [InspectorTab] {
        var tabs: [InspectorTab] = [.explained, .raw, .definition]
        if liveSeries != nil { tabs.append(.statistics) }
        tabs.append(.json)
        return tabs
    }

    /// The live value replaces the stored one while a stream runs.
    private var record: MeasurementRecord? {
        if case .measurement(let record) = item { return liveSeries?.latest ?? record }
        return nil
    }

    // MARK: Header

    @ViewBuilder var header: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            switch item {
            case .troubleCode(let dtc):
                DTCCodeText(displayCode: dtc.displayCode, size: 30)
                Text(dtc.title ?? "Keine Beschreibung hinterlegt")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(dtc.title == nil ? Palette.textSecondary : Palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                HStack(spacing: Spacing.l) {
                    SeverityFlag(severity: group(of: dtc)?.severity ?? dtc.severity, font: .system(size: 13, weight: .semibold))
                    StateChip(state: groupState(of: dtc))
                }
                ConfidenceBadge(confidence: confidence)
                if let status = dtc.statusByte {
                    StatusBitStrip(byte: status)
                }
                locationMap(moduleAddress: dtc.module)
            default:
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                headerValue
                ConfidenceBadge(confidence: confidence)
                if case .module(let module) = item {
                    locationMap(moduleAddress: module.requestID)
                }
            }
        }
    }

    /// The fault as the list shows it: the same code in the same module across all sources.
    private func group(of dtc: ReportDTC) -> FaultGroup? {
        report.flatMap { report in FaultGroup.groups(from: report).first { group in group.entries.contains { $0.id == dtc.id } } }
    }

    private func groupState(of dtc: ReportDTC) -> String {
        guard let group = group(of: dtc) else { return dtc.state }
        return group.isActive ? "aktiv" : group.primary.state
    }

    /// Where the module sits in the car, the same drawing as the cockpit, the module ringed.
    @ViewBuilder private func locationMap(moduleAddress: String) -> some View {
        if let report, let module = report.module(for: moduleAddress) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Lage im Fahrzeug: \(module.acronym ?? module.requestID), \(module.name)")
                    .font(.obdCaption)
                    .foregroundStyle(Palette.textSecondary)
                TrackMap(markers: MapMarker.from(report: report), selection: module.id, showTags: false)
                    .frame(height: 230)
                    .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Radius.tile, style: .continuous).strokeBorder(Palette.hairline))
            }
        } else if moduleAddress.hasPrefix("7E") {
            Label("Gemeldet über die genormte Abgasdiagnose (OBD), Steuergerät \(moduleAddress).", systemImage: "engine.combustion")
                .font(.obdCaption)
                .foregroundStyle(Palette.textSecondary)
        }
    }

    private var title: String {
        switch item {
        case .troubleCode(let dtc): "\(dtc.displayCode) · \(dtc.title ?? "Keine Beschreibung hinterlegt")"
        case .measurement(let record): record.name
        case .module(let module): module.acronym.map { "\($0) · \(module.name)" } ?? module.name
        case .reading(let reading): "\(reading.did) · \(reading.name)"
        }
    }

    private var confidence: Confidence {
        switch item {
        case .troubleCode(let dtc): dtc.titleConfidence ?? .unknown
        case .measurement(let record): record.definition.confidence
        case .module(let module): module.nameConfidence
        case .reading(let reading): reading.confidence
        }
    }

    @ViewBuilder private var headerValue: some View {
        switch item {
        case .troubleCode(let dtc):
            HStack(spacing: Spacing.s) {
                SeverityBadge(severity: dtc.severity)
                StateChip(state: dtc.state)
            }
        case .measurement:
            if let record { ValueText(number: record.displayNumber, unit: record.displayUnit, font: .obdValueMedium) }
        case .module(let module):
            Text("\(module.bus.shortName) · \(module.requestID) → \(module.responseID)").font(.timing(14, .semibold)).foregroundStyle(Palette.textSecondary)
        case .reading(let reading):
            Text(reading.displayValue).font(.timing(15, .semibold)).foregroundStyle(Palette.textPrimary).textSelection(.enabled)
        }
    }

    // MARK: Tabs

    @ViewBuilder func body(for tab: InspectorTab) -> some View {
        switch tab {
        case .explained: explained
        case .raw: raw
        case .definition: definition
        case .statistics: statistics
        case .json: json
        }
    }

    @ViewBuilder private var explained: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            switch item {
            case .troubleCode(let dtc):
                if let explanation = dtc.explanation {
                    ExplanationBlock(title: "Was bedeutet das?", text: explanation.what)
                    ExplanationBlock(title: "Wie dringend? Einschätzung der Wissensbasis", text: explanation.urgency)
                    if !explanation.causes.isEmpty {
                        ExplanationBlock(title: "Mögliche Ursachen", text: explanation.causes.map { "• \($0)" }.joined(separator: "\n"))
                    }
                } else {
                    Text("Für diesen Code ist keine geprüfte Erklärung hinterlegt.").font(.obdBody).foregroundStyle(Palette.textSecondary)
                }
                let reasons = (group(of: dtc)?.entries.flatMap(\.severityReasons) ?? dtc.severityReasons)
                ExplanationBlock(title: "Warum \((group(of: dtc)?.severity ?? dtc.severity).german)?",
                                 text: reasons.isEmpty ? "Für diese Stufe ist keine Begründung gespeichert." : Array(NSOrderedSet(array: reasons)).compactMap { $0 as? String }.joined(separator: " "))
                KeyValueGrid(rows: [
                    KeyValueRow(label: "System", value: dtc.system),
                    KeyValueRow(label: "Herkunft", value: dtc.origin),
                    KeyValueRow(label: "Teilsystem", value: dtc.subsystem ?? "nicht genormt"),
                    KeyValueRow(label: "Fehlerart", value: [dtc.failureTypeCategory, dtc.failureTypeDetail].compactMap { $0 }.joined(separator: ": ").nonEmpty ?? "keine Angabe"),
                    KeyValueRow(label: "Zustand", value: groupState(of: dtc)),
                    KeyValueRow(label: "Gemeldet von", value: (group(of: dtc)?.entries.map { "\($0.source.german): \($0.state)" } ?? [dtc.source.german]).joined(separator: "\n")),
                ])
            case .measurement:
                if let record {
                    VStack(alignment: .leading, spacing: Spacing.s) {
                        ForEach(Array(record.fields.enumerated()), id: \.offset) { _, field in
                            HStack(alignment: .firstTextBaseline) {
                                Text(field.label).font(.obdBody).foregroundStyle(Palette.textSecondary)
                                Spacer()
                                Text(field.value.displayText).font(.obdMono).foregroundStyle(Palette.textPrimary).textSelection(.enabled)
                            }
                        }
                    }
                    KeyValueGrid(rows: [
                        KeyValueRow(label: "Steuergerät", value: record.provenance.ecu, mono: true),
                        KeyValueRow(label: "Bus", value: record.provenance.bus?.german ?? "nicht bekannt"),
                        KeyValueRow(label: "Gelesen", value: Fmt.date(record.provenance.timestamp)),
                    ])
                }
            case .module(let module):
                KeyValueGrid(rows: [
                    KeyValueRow(label: "Name", value: module.name),
                    KeyValueRow(label: "Kürzel", value: module.acronym ?? "nicht hinterlegt", mono: true),
                    KeyValueRow(label: "Bus", value: module.bus.german),
                    KeyValueRow(label: "Kennungen", value: "\(module.identification.count) gelesen, \(module.unsupportedIdentifiers) nicht unterstützt"),
                    KeyValueRow(label: "Fehler", value: "\(module.troubleCodes.count) Einträge"),
                    KeyValueRow(label: "Fehlerspeicher", value: module.troubleCodeSupport ?? "gelesen"),
                ])
            case .reading(let reading):
                KeyValueGrid(rows: readingRows(reading))
            }
        }
    }

    @ViewBuilder private var raw: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            switch item {
            case .troubleCode(let dtc):
                if let status = dtc.statusByte {
                    BitTable(byte: status)
                } else {
                    Text("OBD-Fehlercodes (Dienste 03, 07, 0A) haben kein Statusbyte. Die Liste, in der der Code steht, bestimmt seinen Zustand.")
                        .font(.obdBody).foregroundStyle(Palette.textSecondary).fixedSize(horizontal: false, vertical: true)
                }
                KeyValueGrid(rows: [
                    KeyValueRow(label: "Code", value: dtc.code, mono: true),
                    KeyValueRow(label: "Fehlerart (FTB)", value: dtc.failureType.map { "0x\($0)" } ?? "keine", mono: true),
                    KeyValueRow(label: "Steuergerät", value: dtc.module, mono: true),
                ])
                if let snapshot = dtc.snapshotHex {
                    RawBlock(title: "Umgebungsdaten (19 04)") { HexView(hex: snapshot) }
                }
                if let extended = dtc.extendedDataHex {
                    RawBlock(title: "Erweiterte Daten (19 06)") { HexView(hex: extended) }
                }
            case .measurement:
                if let record {
                    RawBlock(title: "Anfrage", copy: record.provenance.requestHex) { HexView(hex: record.provenance.requestHex) }
                    RawBlock(title: "Antwort, Datenbytes markiert", copy: record.provenance.responseHex) {
                        HexView(hex: record.provenance.responseHex, highlight: dataRange(record))
                    }
                }
            case .module(let module):
                KeyValueGrid(rows: [
                    KeyValueRow(label: "Anfrage-ID", value: module.requestID, mono: true),
                    KeyValueRow(label: "Antwort-ID", value: module.responseID, mono: true),
                    KeyValueRow(label: "Antwortzeit", value: "\(module.responseMilliseconds) ms"),
                    KeyValueRow(label: "Kennung", value: module.id, mono: true),
                ])
                if !module.issues.isEmpty {
                    ExplanationBlock(title: "Auffälligkeiten", text: module.issues.joined(separator: "\n"))
                }
            case .reading(let reading):
                RawBlock(title: "Anfrage", copy: reading.requestHex) { HexView(hex: reading.requestHex) }
                if let response = reading.responseHex {
                    RawBlock(title: "Antwort, Datenbytes markiert", copy: response) {
                        HexView(hex: response, highlight: reading.status == .value ? 3..<Int.max : nil)
                    }
                } else {
                    StateLabel(state: .noResponse)
                }
            }
        }
    }

    @ViewBuilder private var definition: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            switch item {
            case .troubleCode(let dtc):
                KeyValueGrid(rows: [
                    KeyValueRow(label: "Aufbau", value: "SAE J2012: Buchstabe für das System, dann vier Ziffern. Die erste Ziffer zeigt, ob der Code genormt (0, 2) oder herstellerspezifisch (1, 3) ist."),
                    KeyValueRow(label: "Beschreibung aus", value: dtc.titleSource ?? "keine Quelle"),
                    KeyValueRow(label: "Erklärung aus", value: dtc.explanation?.source ?? "keine Erklärung hinterlegt"),
                ])
                if let explanation = dtc.explanation {
                    ConfidenceBadge(confidence: explanation.confidence)
                }
            case .measurement:
                if let record {
                    KeyValueGrid(rows: [
                        KeyValueRow(label: "Norm", value: record.definition.reference),
                        KeyValueRow(label: "Formel", value: record.definition.formula, mono: true, note: "A, B, C, D sind die Datenbytes der Antwort"),
                        KeyValueRow(label: "Ungerundet", value: record.primaryValue?.numericValue.map { "\($0)" } ?? record.primaryValue?.displayText ?? "kein Wert", mono: true),
                        KeyValueRow(label: "Anzeige", value: "\(record.displayDecimals) Nachkommastellen, fest für diese Messgröße"),
                        KeyValueRow(label: "Kennung", value: record.id, mono: true),
                    ])
                }
            case .module(let module):
                KeyValueGrid(rows: [
                    KeyValueRow(label: "Name aus", value: module.nameSource),
                    KeyValueRow(label: "Einbauort", value: module.zone.map(zoneName) ?? "nicht hinterlegt", note: "Typischer Ort, kann je Fahrzeug abweichen"),
                ])
            case .reading(let reading):
                KeyValueGrid(rows: [
                    KeyValueRow(label: "Kennung (DID)", value: reading.did, mono: true),
                    KeyValueRow(label: "Dienst", value: "UDS 22, Daten nach Kennung lesen (ISO 14229-1)"),
                    KeyValueRow(label: "Zustand", value: reading.status == .value ? "Wert gelesen" : reading.status == .negative ? "abgelehnt" : "keine Antwort"),
                ])
            }
        }
    }

    @ViewBuilder private var statistics: some View {
        if let series = liveSeries {
            KeyValueGrid(rows: [
                KeyValueRow(label: "Aktuell", value: "\(series.format(series.latestValue)) \(series.unit)", mono: true),
                KeyValueRow(label: "Minimum", value: "\(series.format(series.minimum)) \(series.unit)", mono: true),
                KeyValueRow(label: "Maximum", value: "\(series.format(series.maximum)) \(series.unit)", mono: true),
                KeyValueRow(label: "Mittel", value: "\(series.format(series.mean)) \(series.unit)", mono: true, note: "aus allen \(series.sampleCount) Werten seit Start"),
                KeyValueRow(label: "Im Speicher", value: "\(series.points.count) von höchstens \(LiveSeries.capacity) Punkten"),
            ])
        }
    }

    @ViewBuilder private var json: some View {
        let text = jsonText
        VStack(alignment: .leading, spacing: Spacing.s) {
            Button("JSON kopieren", systemImage: "doc.on.doc") { copyToPasteboard(text) }
                .controlSize(.small)
            Text(text)
                .font(.obdMono)
                .foregroundStyle(Palette.textPrimary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var jsonText: String {
        let encoder = ReportCoding.encoder()
        let data: Data?
        switch item {
        case .troubleCode(let dtc): data = try? encoder.encode(dtc)
        case .measurement: data = record.flatMap { try? encoder.encode($0) }
        case .module(let module): data = try? encoder.encode(module)
        case .reading(let reading): data = try? encoder.encode(reading)
        }
        return data.flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }

    // MARK: Helpers

    /// Positive service 01 and 02 responses start with `41 <pid>` or `42 <pid> <frame>`.
    private func dataRange(_ record: MeasurementRecord) -> Range<Int>? {
        guard let first = (try? Hex.decode(record.provenance.responseHex))?.first else { return nil }
        switch first {
        case 0x41: return 2..<Int.max
        case 0x42: return 3..<Int.max
        default: return nil
        }
    }

    private func readingRows(_ reading: DIDReading) -> [KeyValueRow] {
        var rows = [KeyValueRow(label: "Wert", value: reading.displayValue, mono: true)]
        if let part = reading.partNumber {
            rows.append(KeyValueRow(label: "Teilenummer", value: part.text, mono: true,
                                    note: "Präfix \(part.prefix), Basis \(part.base), Suffix \(part.suffix)"))
        }
        if let owner = reading.partNumberModule {
            rows.append(KeyValueRow(label: "Basis gehört zu", value: owner))
        }
        if let vin = reading.vin {
            rows.append(KeyValueRow(label: "FIN", value: vin, mono: true))
        }
        if let code = reading.negativeResponseCode {
            rows.append(KeyValueRow(label: "Ablehnung", value: "0x\(code) \(reading.negativeResponseText ?? "")", mono: true))
        }
        return rows
    }

    private func zoneName(_ zone: VehicleZone) -> String {
        switch zone {
        case .engineBay: "Motorraum"
        case .front: "Front"
        case .cabinFront: "Innenraum vorn"
        case .cabinCenter: "Innenraum Mitte"
        case .cabinRear: "Innenraum hinten"
        case .doorsLeft: "Türen links"
        case .doorsRight: "Türen rechts"
        case .rear: "Heck"
        case .roof: "Dach"
        }
    }
}

struct RawBlock<Content: View>: View {
    let title: String
    var copy: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack {
                Text(title).font(.obdLabel).foregroundStyle(Palette.textSecondary)
                Spacer()
                if let copy {
                    Button("Kopieren", systemImage: "doc.on.doc") { copyToPasteboard(copy) }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                        .labelStyle(.iconOnly)
                        .help("Hex kopieren")
                }
            }
            content
                .padding(Spacing.m)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).strokeBorder(Palette.hairline))
        }
    }
}

extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
