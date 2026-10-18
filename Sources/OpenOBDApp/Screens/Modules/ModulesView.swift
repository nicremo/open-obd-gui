import DiagnosticEngine
import OBDCore
import OpenOBDAppCore
import SwiftUI

/// List by bus on the left, detail of the selected module on the right.
struct ModulesView: View {
    @Environment(AppModel.self) private var model
    @SceneStorage("modules.selection") private var selectionRaw = ""

    var body: some View {
        if let report = model.report, !report.modules.isEmpty {
            HStack(spacing: 0) {
                moduleList(report)
                    .frame(minWidth: 200, idealWidth: 280, maxWidth: 300)
                Divider()
                if let module = selected(in: report) {
                    ModuleDetail(module: module, report: report)
                        .id(module.id)
                } else {
                    EmptyState(symbol: "cpu", title: "Steuergerät wählen", message: "Links ein Steuergerät wählen, um Kennungen, Fehler und Konfiguration zu sehen.")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(Palette.background)
            .onAppear { followInspector(report) }
            .onChange(of: model.showInspector) { _, open in if open { followInspector(report) } }
        } else if model.report != nil {
            ScreenScaffold(title: "Steuergeräte") {
                EmptyState(symbol: "cpu", title: "Keine Steuergeräte gefunden",
                           message: "Kein Steuergerät hat auf die Suche geantwortet. Zündung an? Bei einem schnellen Scan wird der MS-CAN nicht durchsucht.")
            }
        } else {
            NoReportView(section: .modules)
        }
    }

    /// With the inspector open it shows the selected module: its most urgent fault card, or the module itself.
    private func followInspector(_ report: VehicleReport) {
        guard model.showInspector, let module = selected(in: report) else { return }
        if let group = FaultGroup.groups(from: report.faults(of: module.requestID)).first {
            model.inspect(.troubleCode(group.primary))
        } else {
            model.inspect(.module(module))
        }
    }

    private func selected(in report: VehicleReport) -> ReportModule? {
        report.modules.first { $0.id == selectionRaw } ?? report.modules.first
    }

    private func moduleList(_ report: VehicleReport) -> some View {
        List(selection: Binding<String?>(get: { selected(in: report)?.id }, set: { id in
            selectionRaw = id ?? ""
            followInspector(report)
        })) {
            ForEach(BusKind.allCases, id: \.self) { bus in
                let modules = report.modules.filter { $0.bus == bus }
                if !modules.isEmpty {
                    Section("\(bus.shortName) · \(modules.count)") {
                        ForEach(modules) { module in
                            ModuleRow(module: module, faults: FaultGroup.groups(from: report.faults(of: module.requestID)))
                                .tag(module.id)
                                .contextMenu {
                                    Button("Technik anzeigen") { model.inspect(.module(module)) }
                                    Button("Adresse kopieren") { copyToPasteboard(module.requestID) }
                                }
                        }
                    }
                }
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .background(Palette.surface)
    }
}

struct ModuleRow: View {
    let module: ReportModule
    let faults: [FaultGroup]

    var body: some View {
        HStack(spacing: Spacing.m) {
            Text(module.acronym ?? "?")
                .font(.obdCode)
                .foregroundStyle(Palette.textPrimary)
                .frame(width: 52, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text(module.name).font(.obdBody).foregroundStyle(Palette.textPrimary).lineLimit(1)
                    .help(module.name)
                Text("\(module.requestID) · \(module.responseMilliseconds) ms").font(.obdCaption.monospacedDigit()).foregroundStyle(Palette.textTertiary)
            }
            Spacer(minLength: Spacing.xs)
            if !module.nameConfidence.isFact {
                ConfidenceBadge(confidence: module.nameConfidence, compact: true)
            }
            if !faults.isEmpty {
                FlagGlyph(flag: Flag(faults.map(\.severity).max()), width: 12)
                CountBadge(count: faults.count, color: Palette.textPrimary)
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(module.acronym ?? "") \(module.name), \(faults.count) Fehler")
    }
}

struct ModuleDetail: View {
    @Environment(AppModel.self) private var model
    let module: ReportModule
    let report: VehicleReport

    var body: some View {
        let faults = FaultGroup.groups(from: report.faults(of: module.requestID))
        ScreenScaffold(title: module.acronym.map { "\($0) · \(module.name)" } ?? module.name,
                       subtitle: "\(module.bus.german) · Anfrage \(module.requestID) · Antwort \(module.responseID) · \(module.responseMilliseconds) ms") {
            Button("Technik", systemImage: "sidebar.trailing") { model.inspect(.module(module)) }
        } content: {
            HStack(spacing: Spacing.s) {
                ConfidenceBadge(confidence: module.nameConfidence)
                Text("Name: \(module.nameSource)").font(.obdCaption).foregroundStyle(Palette.textTertiary)
            }
            Panel(title: "Fehler", subtitle: faults.isEmpty ? nil : "\(faults.count) gespeichert") {
                if faults.isEmpty {
                    Label(module.troubleCodeSupport ?? "Kein Fehler gespeichert.", systemImage: "checkmark.seal")
                        .font(.obdBody)
                        .foregroundStyle(module.troubleCodeSupport == nil ? Palette.ok : Palette.textSecondary)
                } else {
                    VStack(spacing: 0) {
                        ForEach(faults) { group in
                            CompactFaultRow(group: group, moduleLabel: group.primary.state)
                                .onTapGesture { model.inspect(.troubleCode(group.primary)) }
                            if group.id != faults.last?.id { Divider() }
                        }
                    }
                }
            }
            Panel(title: "Kennungen", subtitle: identificationSubtitle,
                  info: "Daten, die das Steuergerät über sich selbst meldet (UDS-Dienst 22). Teilenummern sind hervorgehoben.") {
                if module.identification.isEmpty {
                    StateLabel(state: .notRead)
                    Text("Kennungen werden ab dem Standard-Scan gelesen.").font(.obdCaption).foregroundStyle(Palette.textTertiary)
                } else {
                    ReadingTable(readings: module.identification) { model.inspect(.reading($0)) }
                }
            }
            if !module.asBuilt.isEmpty {
                Panel(title: "Konfigurationsblöcke", subtitle: "\(module.asBuilt.count) Blöcke",
                      info: "Herstellerspezifische Konfiguration (As-Built). Die Bedeutung der einzelnen Bits ist nicht entschlüsselt, angezeigt werden nur die Rohdaten.") {
                    VStack(alignment: .leading, spacing: Spacing.s) {
                        ForEach(module.asBuilt) { reading in
                            HStack(alignment: .firstTextBaseline, spacing: Spacing.m) {
                                Text(reading.did).font(.obdMonoStrong).frame(width: 52, alignment: .leading)
                                Text(reading.hex ?? reading.displayValue)
                                    .font(.obdMono)
                                    .foregroundStyle(Palette.textPrimary)
                                    .textSelection(.enabled)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { model.inspect(.reading(reading)) }
                        }
                        ConfidenceBadge(confidence: .unknown)
                    }
                }
            }
            if !module.issues.isEmpty {
                Panel(title: "Auffälligkeiten") {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        ForEach(module.issues, id: \.self) { issue in
                            Label(issue, systemImage: "exclamationmark.circle").font(.obdBody).foregroundStyle(Palette.warningText)
                        }
                    }
                }
            }
        }
    }

    private var identificationSubtitle: String {
        var parts = ["\(module.identification.count) gelesen"]
        if module.unsupportedIdentifiers > 0 { parts.append("\(module.unsupportedIdentifiers) nicht unterstützt") }
        return parts.joined(separator: " · ")
    }
}

/// DID readings with distinct states for value, rejected and no response.
struct ReadingTable: View {
    let readings: [DIDReading]
    let onInspect: (DIDReading) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(readings) { reading in
                HStack(alignment: .firstTextBaseline, spacing: Spacing.m) {
                    Text(reading.did).font(.obdMono).foregroundStyle(Palette.textTertiary).frame(width: 48, alignment: .leading)
                    Text(reading.name).font(.obdBody).foregroundStyle(Palette.textSecondary).frame(minWidth: 100, idealWidth: 220, maxWidth: 220, alignment: .leading).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    value(reading)
                    Spacer(minLength: Spacing.s)
                    ConfidenceBadge(confidence: reading.confidence, compact: true)
                }
                .padding(.vertical, 6)
                .contentShape(Rectangle())
                .onTapGesture { onInspect(reading) }
                .contextMenu {
                    Button("Technik anzeigen") { onInspect(reading) }
                    Button("Wert kopieren") { copyToPasteboard(reading.displayValue) }
                }
                if reading.id != readings.last?.id { Divider() }
            }
        }
    }

    @ViewBuilder
    private func value(_ reading: DIDReading) -> some View {
        switch reading.status {
        case .value:
            if let part = reading.partNumber {
                VStack(alignment: .leading, spacing: 1) {
                    Text(part.text).font(.obdMonoStrong).foregroundStyle(Palette.textPrimary).textSelection(.enabled)
                        .fixedSize()
                    if let owner = reading.partNumberModule {
                        Text(owner).font(.obdCaption).foregroundStyle(Palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else {
                Text(reading.displayValue).font(.obdMono).foregroundStyle(Palette.textPrimary).textSelection(.enabled).lineLimit(2)
            }
        case .negative:
            StateLabel(state: .rejected(reading.negativeResponseText ?? reading.negativeResponseCode ?? "unbekannt"), font: .obdCaption)
        case .noResponse:
            StateLabel(state: .noResponse, font: .obdCaption)
        }
    }
}
