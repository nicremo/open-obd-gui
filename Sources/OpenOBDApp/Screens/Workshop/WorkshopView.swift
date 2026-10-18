import AdapterKit
import DiagnosticEngine
import OBDCore
import OpenOBDAppCore
import SwiftUI

/// Raw request with read-only check, protocol traffic, last scan steps, adapter.
struct WorkshopView: View {
    @Environment(AppModel.self) private var model
    @State private var width: CGFloat = 1200

    var body: some View {
        ScreenScaffold(title: "Werkstatt", subtitle: "Für Profis: Rohanfragen und der komplette Verkehr zwischen Adapter und Fahrzeug") {
            let layout = width >= 900
                ? AnyLayout(HStackLayout(alignment: .top, spacing: Spacing.l))
                : AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.l))
            layout {
                VStack(spacing: Spacing.l) {
                    RawRequestPanel()
                    TrafficPanel()
                }
                VStack(spacing: Spacing.l) {
                    ConnectionPanel()
                    if let report = model.report {
                        ScanStepsPanel(steps: report.meta.steps, total: report.meta.durationMilliseconds)
                    }
                }
                .frame(minWidth: 240, idealWidth: 340, maxWidth: width >= 900 ? 340 : .infinity)
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }
}

struct RawRequestPanel: View {
    @Environment(AppModel.self) private var model
    @SceneStorage("workshop.request") private var request = "22 F1 90"
    @SceneStorage("workshop.module") private var module = "7E0"
    @SceneStorage("workshop.bus") private var busRaw = BusKind.hsCAN.rawValue
    @SceneStorage("workshop.functional") private var functional = false
    @State private var outcome: RawOutcome?
    @State private var sending = false

    private static let examples: [(title: String, request: String, functional: Bool)] = [
        ("FIN (UDS)", "22 F1 90", false),
        ("Teilenummer", "22 F1 88", false),
        ("Fehlerspeicher", "19 02 AF", false),
        ("Drehzahl (OBD)", "01 0C", true),
        ("FIN (OBD)", "09 02", true),
    ]

    var body: some View {
        Panel(title: "Rohanfrage", info: "Sendet eine einzelne Diagnoseanfrage. Vor dem Senden prüft die App, ob der Dienst nur liest.") {
            Label("Nur lesend", systemImage: "lock.shield").font(.obdCaption).foregroundStyle(Palette.ok)
        } content: {
            VStack(alignment: .leading, spacing: Spacing.m) {
                HStack(spacing: Spacing.m) {
                    TextField("Anfrage in Hex, zum Beispiel 22 F1 90", text: $request)
                        .font(.obdMono)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(send)
                    TextField("Adresse", text: $module)
                        .font(.obdMono)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 70)
                        .disabled(functional)
                        .help("Anfrageadresse des Steuergeräts, drei Hex-Ziffern")
                    Picker("Bus", selection: $busRaw) {
                        ForEach(BusKind.allCases, id: \.rawValue) { Text($0.shortName).tag($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 150)
                }
                HStack(spacing: Spacing.m) {
                    Toggle("Funktional an alle OBD-Steuergeräte (7DF)", isOn: $functional)
                        .toggleStyle(.checkbox)
                        .font(.obdBody)
                    Spacer()
                    Button("Erneut senden", systemImage: "arrow.clockwise", action: send)
                        .keyboardShortcut(.return, modifiers: [.command, .shift])
                        .disabled(outcome == nil || sending)
                    Button("Senden", systemImage: "paperplane.fill", action: send)
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.return, modifiers: .command)
                        .disabled(sending || model.isOccupied)
                }
                HStack(spacing: Spacing.xs) {
                    Text("Beispiele").font(.obdCaption).foregroundStyle(Palette.textTertiary)
                    ForEach(Self.examples, id: \.request) { example in
                        Button(example.title) {
                            request = example.request
                            functional = example.functional
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                Text("Erlaubt sind nur lesende Dienste: 01, 02, 03, 06, 07, 09, 0A, 22, 19 (Lesefunktionen), 3E und 10 01. Alles andere lehnt die App ab, bevor etwas gesendet wird.")
                    .font(.obdCaption)
                    .foregroundStyle(Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                if sending {
                    ProgressView().controlSize(.small)
                } else if let outcome {
                    OutcomeView(outcome: outcome)
                }
            }
        }
    }

    private func send() {
        sending = true
        let bus = BusKind(rawValue: busRaw) ?? .hsCAN
        Task {
            outcome = await model.raw(request, module: module, bus: bus, functional: functional)
            sending = false
        }
    }
}

struct OutcomeView: View {
    let outcome: RawOutcome

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack {
                Text("Anfrage").font(.obdLabel).foregroundStyle(Palette.textSecondary)
                Text(outcome.request).font(.obdMono).textSelection(.enabled)
                Spacer()
                Button("Kopieren", systemImage: "doc.on.doc") {
                    copyToPasteboard((["> \(outcome.request)"] + outcome.lines + [outcome.error].compactMap { $0 }).joined(separator: "\n"))
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
            }
            if let error = outcome.error {
                Label(error, systemImage: "hand.raised.fill")
                    .font(.obdBody)
                    .foregroundStyle(Palette.fault)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(Array(outcome.lines.enumerated()), id: \.offset) { _, line in
                    Text(line).font(.obdMono).foregroundStyle(Palette.textPrimary).textSelection(.enabled)
                }
            }
        }
        .padding(Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surfaceRaised, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
    }
}

enum TrafficFilter: String, CaseIterable {
    case all, sent, received, failed

    var title: String {
        switch self {
        case .all: "Alle"
        case .sent: "Gesendet"
        case .received: "Empfangen"
        case .failed: "Fehler"
        }
    }

    func matches(_ line: TrafficLine) -> Bool {
        switch self {
        case .all: true
        case .sent: line.direction == .sent
        case .received: line.direction == .received
        case .failed: line.direction == .failed
        }
    }
}

/// Protocol traffic as a dense, raw first list.
struct TrafficPanel: View {
    @Environment(AppModel.self) private var model
    @State private var filter: TrafficFilter = .all
    @State private var frozen: [TrafficLine]?

    var body: some View {
        let source = frozen ?? model.traffic
        let lines = source.filter { filter.matches($0) }
        Panel(title: "Protokollverkehr", subtitle: "\(model.traffic.count) Zeilen, die ältesten werden ab 800 verworfen") {
            HStack(spacing: Spacing.s) {
                Button(frozen == nil ? "Anhalten" : "Fortsetzen", systemImage: frozen == nil ? "pause" : "play") {
                    frozen = frozen == nil ? model.traffic : nil
                }
                Button("Kopieren", systemImage: "doc.on.doc") {
                    copyToPasteboard(lines.map { "\(Fmt.time($0.time)) \(Self.arrow($0.direction)) \($0.text.trimmingCharacters(in: .whitespacesAndNewlines))" }.joined(separator: "\n"))
                }
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
        } content: {
            VStack(alignment: .leading, spacing: Spacing.s) {
                FilterChipBar(options: TrafficFilter.allCases.map { option in
                    (option, option.title, source.filter { option.matches($0) }.count)
                }, selection: $filter)
                if lines.isEmpty {
                    Text("Noch kein Verkehr. Verbinden oder auslesen, dann erscheinen hier alle Befehle und Antworten.")
                        .font(.obdBody)
                        .foregroundStyle(Palette.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 120)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 1) {
                                ForEach(lines) { line in
                                    HStack(alignment: .firstTextBaseline, spacing: Spacing.m) {
                                        Text(Fmt.time(line.time)).foregroundStyle(Palette.textTertiary)
                                        Text(Self.arrow(line.direction)).foregroundStyle(Self.color(line.direction)).frame(width: 14)
                                        Text(line.text.trimmingCharacters(in: .whitespacesAndNewlines))
                                            .foregroundStyle(line.direction == .failed ? Palette.fault : Palette.textPrimary)
                                            .textSelection(.enabled)
                                    }
                                    .font(.obdMono)
                                    .id(line.id)
                                }
                            }
                            .padding(Spacing.s)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(height: 340)
                        .background(Palette.background, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                        .onChange(of: lines.last?.id) { _, last in
                            if frozen == nil, let last { proxy.scrollTo(last, anchor: .bottom) }
                        }
                        .onAppear {
                            if let last = lines.last?.id { proxy.scrollTo(last, anchor: .bottom) }
                        }
                    }
                }
            }
        }
    }

    static func arrow(_ direction: TrafficEvent.Direction) -> String {
        switch direction {
        case .sent: "→"
        case .received: "←"
        case .failed: "!"
        }
    }

    static func color(_ direction: TrafficEvent.Direction) -> Color {
        switch direction {
        case .sent: Palette.live
        case .received: Palette.ok
        case .failed: Palette.fault
        }
    }
}

struct ConnectionPanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Panel(title: "Verbindung", subtitle: model.choice.title) {
            VStack(alignment: .leading, spacing: Spacing.m) {
                HStack(spacing: Spacing.s) {
                    Circle().fill(PhaseStyle.color(model.phase, connected: model.adapter != nil)).frame(width: 8, height: 8)
                    Text(model.statusLine).font(.obdBody).foregroundStyle(Palette.textPrimary).fixedSize(horizontal: false, vertical: true)
                }
                if let adapter = model.adapter {
                    KeyValueGrid(rows: [
                        KeyValueRow(label: "Gerät", value: adapter.identity.displayName),
                        KeyValueRow(label: "Firmware", value: adapter.identity.stnFirmware ?? adapter.identity.elmVersion, mono: true),
                        KeyValueRow(label: "Spannung", value: Fmt.voltage(adapter.voltage)),
                        KeyValueRow(label: "MS-CAN", value: adapter.msCANAvailable ? "verfügbar" : "nicht verfügbar"),
                        KeyValueRow(label: "Leitung", value: adapter.link, mono: true),
                    ])
                }
                if !model.candidates.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Gefundene Schnittstellen").font(.obdLabel).foregroundStyle(Palette.textSecondary)
                        ForEach(model.candidates, id: \.path) { candidate in
                            Text("\(candidate.path) · \(candidate.reason)")
                                .font(.obdCaption)
                                .foregroundStyle(candidate.isLikelyOBDAdapter ? Palette.textPrimary : Palette.textTertiary)
                        }
                    }
                }
                AgentAccessRow(status: model.agentBridge, activity: model.agentActivity)
                HStack {
                    Button("Verbinden") { Task { await model.connect() } }.disabled(model.isOccupied)
                    Button("Trennen") { Task { await model.disconnect() } }.disabled(model.adapter == nil)
                    Button("Neu suchen") { model.refreshDevices() }
                }
                .controlSize(.small)
            }
        }
    }
}

/// Whether agents can read through the app (`openobd --via-app`, MCP with route auto or app).
struct AgentAccessRow: View {
    let status: AgentBridgeStatus
    let activity: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(title, systemImage: "terminal")
                .font(.obdLabel)
                .foregroundStyle(color)
            Text(detail)
                .font(.obdCaption)
                .foregroundStyle(Palette.textSecondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .help("Agenten nutzen dieselbe Sitzung wie die App: openobd --via-app oder das MCP-Werkzeug mit route app.")
    }

    private var title: String {
        switch status {
        case .off: "Agent-Zugang aus"
        case .ready: activity.map { "Agent liest: \($0)" } ?? "Agent-Zugang bereit"
        case .failed: "Agent-Zugang nicht verfügbar"
        }
    }

    private var detail: String {
        switch status {
        case .off: "Start ohne --no-agent-bridge schaltet ihn ein."
        case .ready(let path): path
        case .failed(let message): message
        }
    }

    private var color: Color {
        switch status {
        case .off: Palette.textSecondary
        case .ready: activity == nil ? Palette.textPrimary : Palette.live
        case .failed: Palette.warningText
        }
    }
}

struct ScanStepsPanel: View {
    let steps: [StepRecord]
    let total: Int

    var body: some View {
        Panel(title: "Ablauf des letzten Scans", subtitle: "\(steps.count) Schritte · \(total) ms") {
            VStack(alignment: .leading, spacing: Spacing.s) {
                ForEach(Array(steps.enumerated()), id: \.offset) { _, step in
                    HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                        Image(systemName: symbol(step.outcome)).foregroundStyle(color(step.outcome)).frame(width: 16)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(step.title).font(.obdBody).foregroundStyle(Palette.textPrimary)
                            if !step.detail.isEmpty {
                                Text(step.detail).font(.obdCaption).foregroundStyle(Palette.textTertiary).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Spacer()
                        Text("\(step.durationMilliseconds) ms").font(.obdCaption.monospacedDigit()).foregroundStyle(Palette.textTertiary)
                    }
                }
            }
        }
    }

    private func symbol(_ outcome: StepRecord.Outcome) -> String {
        switch outcome {
        case .ok: "checkmark.circle.fill"
        case .skipped: "minus.circle"
        case .failed: "xmark.octagon.fill"
        }
    }

    private func color(_ outcome: StepRecord.Outcome) -> Color {
        switch outcome {
        case .ok: Palette.ok
        case .skipped: Palette.textTertiary
        case .failed: Palette.fault
        }
    }
}
