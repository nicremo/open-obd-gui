import DiagnosticEngine
import OBDCore
import OpenOBDAppCore
import SwiftUI

/// Identity, readiness, OBD control modules, freeze frame, snapshot, adapter.
struct VehicleView: View {
    @Environment(AppModel.self) private var model
    @State private var width: CGFloat = 1200

    var body: some View {
        if let report = model.report {
            ScreenScaffold(title: report.vehicle.title, subtitle: report.vehicle.vin.map { "FIN \($0)" } ?? "Fahrgestellnummer nicht gelesen") {
                content(report)
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        } else {
            NoReportView(section: .vehicle)
        }
    }

    @ViewBuilder
    private func content(_ report: VehicleReport) -> some View {
        let layout = width >= 860
            ? AnyLayout(HStackLayout(alignment: .top, spacing: Spacing.l))
            : AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.l))
        layout {
            IdentityPanel(vehicle: report.vehicle)
            ReadinessPanel(report: report)
        }
        if !report.obd.ecus.isEmpty {
            Panel(title: "OBD-Steuergeräte", subtitle: report.obd.protocolName.map { "Protokoll \($0)" },
                  info: "Steuergeräte, die auf die genormte Abgasdiagnose (SAE J1979) antworten.") {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    ForEach(report.obd.ecus) { ecu in
                        OBDECUBlock(ecu: ecu)
                        if ecu.id != report.obd.ecus.last?.id { Divider() }
                    }
                }
            }
        }
        let freeze = report.obd.ecus.flatMap(\.freezeFrame)
        if !freeze.isEmpty {
            Panel(title: "Freeze Frame", subtitle: "Momentaufnahme im Augenblick des Fehlers",
                  info: "Werte, die das Motorsteuergerät beim Speichern des Fehlers festgehalten hat (OBD-Dienst 02).") {
                MeasurementTable(records: freeze) { model.inspect(.measurement($0)) }
            }
        }
        let snapshot = report.snapshot
        Panel(title: "Momentaufnahme", subtitle: snapshot.isEmpty ? nil : "\(snapshot.count) Werte zum Zeitpunkt des Scans",
              info: "Alle genormten Messwerte, die das Fahrzeug unterstützt, einmal abgefragt (OBD-Dienst 01).") {
            if snapshot.isEmpty {
                StateLabel(state: .notRead)
                Text("Die Momentaufnahme wird ab dem Standard-Scan gelesen.").font(.obdCaption).foregroundStyle(Palette.textTertiary)
            } else {
                MeasurementTable(records: snapshot) { model.inspect(.measurement($0)) }
            }
        }
        AdapterPanel(adapter: report.adapter, link: report.meta.link)
    }
}

struct IdentityPanel: View {
    let vehicle: ReportVehicle

    var body: some View {
        Panel(title: "Identität", info: "Die Fahrgestellnummer (FIN, VIN) wird nach ISO 3779 zerlegt. Herstellerspezifische Stellen werden nicht geraten.") {
            if let info = vehicle.vinInfo {
                VStack(alignment: .leading, spacing: Spacing.m) {
                    Text(info.vin)
                        .font(.timing(26, .bold))
                        .tracking(1.2)
                        .foregroundStyle(Palette.textPrimary)
                        .textSelection(.enabled)
                    HStack(spacing: Spacing.s) {
                        if info.isValid {
                            Chip(text: "Format gültig", color: Palette.ok, symbol: "checkmark")
                        } else {
                            Chip(text: "Format ungültig", color: Palette.fault, symbol: "xmark")
                        }
                        if let confidence = info.manufacturerConfidence { ConfidenceBadge(confidence: confidence) }
                    }
                    KeyValueGrid(rows: rows(info))
                    if vehicle.vinSources.count > 0 {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Gelesen aus").font(.obdLabel).foregroundStyle(Palette.textSecondary)
                            ForEach(Array(vehicle.vinSources.enumerated()), id: \.offset) { _, source in
                                Text("\(source.source): \(source.vin)").font(.timing(13, .medium)).foregroundStyle(Palette.textSecondary)
                            }
                        }
                    }
                }
            } else {
                StateLabel(state: .noResponse)
                Text("Kein Steuergerät hat eine Fahrgestellnummer gemeldet.").font(.obdCaption).foregroundStyle(Palette.textTertiary)
            }
        }
    }

    private func rows(_ info: VINInfo) -> [KeyValueRow] {
        var rows = [
            KeyValueRow(label: "Hersteller", value: info.manufacturer ?? "nicht hinterlegt", note: "Herstellerkennung \(info.wmi)"),
            KeyValueRow(label: "Region", value: info.region),
            KeyValueRow(label: "Fahrzeugbeschreibung", value: info.vehicleDescriptor, mono: true, note: "Stellen 4 bis 9, herstellerspezifisch"),
            KeyValueRow(label: "Seriennummer", value: info.serial, mono: true, note: "Stellen 12 bis 17"),
            KeyValueRow(label: "Modelljahr", value: info.modelYearCandidates.isEmpty ? "nicht bestimmbar" : info.modelYearCandidates.map(String.init).joined(separator: " oder "),
                        note: info.modelYearNote),
        ]
        if info.checkDigitApplies {
            rows.append(KeyValueRow(label: "Prüfziffer", value: info.checkDigitValid == true ? "stimmt" : "stimmt nicht"))
        } else {
            rows.append(KeyValueRow(label: "Prüfziffer", value: "in Europa nicht vorgeschrieben"))
        }
        return rows
    }
}

struct ReadinessPanel: View {
    let report: VehicleReport

    var body: some View {
        Panel(title: "Bereitschaftstests",
              info: "Selbsttests der Abgasdiagnose (OBD-Dienst 01, PID 01). Nach dem Löschen des Fehlerspeichers oder Abklemmen der Batterie müssen sie erst wieder durchlaufen.") {
            if let readiness = report.primaryReadiness {
                VStack(alignment: .leading, spacing: Spacing.m) {
                    HStack(spacing: Spacing.s) {
                        Chip(text: readiness.ignition.german, color: Palette.textSecondary, symbol: "flame")
                        if let mil = readiness.milOn {
                            Chip(text: mil ? "Motorkontrollleuchte an" : "Motorkontrollleuchte aus", color: mil ? Palette.fault : Palette.ok,
                                 symbol: mil ? "exclamationmark.triangle.fill" : "checkmark")
                        }
                        if let count = readiness.storedDTCCount {
                            Chip(text: "\(count) OBD-Fehler", color: count > 0 ? Palette.warningText : Palette.textSecondary)
                        }
                    }
                    VStack(spacing: 0) {
                        ForEach(readiness.monitors, id: \.name) { monitor in
                            HStack(spacing: Spacing.s) {
                                Image(systemName: symbol(monitor)).foregroundStyle(color(monitor)).frame(width: 18)
                                Text(monitor.name).font(.obdBody).foregroundStyle(monitor.supported ? Palette.textPrimary : Palette.textTertiary)
                                if monitor.continuous {
                                    Text("laufend").font(.obdCaption).foregroundStyle(Palette.textTertiary)
                                }
                                Spacer()
                                Text(monitor.stateGerman).font(.obdLabel).foregroundStyle(color(monitor))
                            }
                            .padding(.vertical, 5)
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
            } else {
                StateLabel(state: .noResponse)
                Text("Kein Steuergerät hat Bereitschaftstests gemeldet.").font(.obdCaption).foregroundStyle(Palette.textTertiary)
            }
        }
    }

    private func symbol(_ monitor: ReadinessReport.Monitor) -> String {
        guard monitor.supported else { return "nosign" }
        return monitor.complete ? "checkmark.circle.fill" : "hourglass.circle"
    }

    private func color(_ monitor: ReadinessReport.Monitor) -> Color {
        guard monitor.supported else { return Palette.textTertiary }
        return monitor.complete ? Palette.ok : Palette.warningText
    }
}

struct OBDECUBlock: View {
    let ecu: ReportOBDECU

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack(spacing: Spacing.s) {
                Text(ecu.address).font(.obdMonoStrong)
                Text(ecu.info?.ecuName ?? "Steuergerät ohne Namen").font(.obdBody).foregroundStyle(Palette.textSecondary)
                Spacer()
                Chip(text: "\(ecu.supportedPIDs.count) Messwerte unterstützt", color: Palette.textSecondary)
            }
            KeyValueGrid(rows: [
                KeyValueRow(label: "Kalibrierung", value: list(ecu.info?.calibrationIDs), mono: true),
                KeyValueRow(label: "Prüfsumme (CVN)", value: list(ecu.info?.calibrationVerificationNumbers), mono: true),
            ])
        }
    }

    private func list(_ values: [String]?) -> String {
        guard let values, !values.isEmpty else { return "nicht gemeldet" }
        return values.joined(separator: ", ")
    }
}

/// Sortable list of measurements.
struct MeasurementTable: View {
    enum SortKey { case name, ecu }

    let records: [MeasurementRecord]
    let onInspect: (MeasurementRecord) -> Void
    @State private var sortKey: SortKey = .name

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Spacing.m) {
                sortButton("Messwert", .name).frame(maxWidth: .infinity, alignment: .leading)
                Text("Wert").frame(width: 160, alignment: .trailing)
                Text("Einheit").frame(width: 60, alignment: .leading)
                sortButton("Steuergerät", .ecu).frame(width: 90, alignment: .leading)
                Text("Herkunft").lineLimit(1).frame(width: 70, alignment: .leading)
            }
            .font(.obdCaption)
            .foregroundStyle(Palette.textTertiary)
            .padding(.vertical, 6)
            Divider()
            ForEach(sorted) { record in
                HStack(spacing: Spacing.m) {
                    Text(record.name).font(.obdBody).foregroundStyle(Palette.textPrimary).frame(maxWidth: .infinity, alignment: .leading).lineLimit(1)
                    Text(record.displayNumber).font(.timing(14, .semibold)).foregroundStyle(Palette.textPrimary).frame(width: 160, alignment: .trailing).lineLimit(1)
                    Text(record.displayUnit).font(.obdCaption).foregroundStyle(Palette.textSecondary).frame(width: 60, alignment: .leading)
                    Text(record.provenance.ecu).font(.timing(13, .medium)).foregroundStyle(Palette.textTertiary).frame(width: 90, alignment: .leading)
                    ConfidenceBadge(confidence: record.definition.confidence, compact: true).frame(width: 70, alignment: .leading)
                }
                .frame(minHeight: 28)
                .contentShape(Rectangle())
                .onTapGesture { onInspect(record) }
                .contextMenu {
                    Button("Technik anzeigen") { onInspect(record) }
                    Button("Wert kopieren") { copyToPasteboard("\(record.name): \(record.displayNumber) \(record.displayUnit)") }
                }
                .accessibilityElement(children: .combine)
                Divider()
            }
        }
    }

    private var sorted: [MeasurementRecord] {
        switch sortKey {
        case .name: records.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
        case .ecu: records.sorted { ($0.provenance.ecu, $0.id) < ($1.provenance.ecu, $1.id) }
        }
    }

    private func sortButton(_ title: String, _ key: SortKey) -> some View {
        Button {
            sortKey = key
        } label: {
            HStack(spacing: 2) {
                Text(title)
                if sortKey == key { Image(systemName: "chevron.down").imageScale(.small) }
            }
        }
        .buttonStyle(.plain)
    }
}

struct AdapterPanel: View {
    let adapter: ReportAdapter
    let link: String

    var body: some View {
        Panel(title: "Adapter", subtitle: link) {
            VStack(alignment: .leading, spacing: Spacing.m) {
                if let identity = adapter.identity {
                    KeyValueGrid(rows: [
                        KeyValueRow(label: "Gerät", value: identity.device ?? "nicht gemeldet"),
                        KeyValueRow(label: "Hersteller", value: identity.manufacturer ?? "nicht gemeldet"),
                        KeyValueRow(label: "Firmware", value: identity.stnFirmware ?? identity.elmVersion, mono: true),
                        KeyValueRow(label: "ELM-Kennung", value: identity.elmVersion, mono: true),
                        KeyValueRow(label: "Seriennummer", value: identity.serialNumber ?? "nicht gemeldet", mono: true),
                        KeyValueRow(label: "Spannung an der OBD-Buchse", value: Fmt.voltage(adapter.voltage)),
                    ])
                } else {
                    StateLabel(state: .noResponse)
                }
                HStack(spacing: Spacing.s) {
                    ForEach(adapter.buses, id: \.bus) { bus in
                        Chip(text: "\(bus.bus.shortName) \(bus.available ? "erreichbar" : "nicht erreichbar")",
                             color: bus.available ? Palette.ok : Palette.textTertiary, symbol: bus.available ? "checkmark" : "nosign")
                            .help(bus.note ?? bus.bus.german)
                    }
                }
            }
        }
    }
}
