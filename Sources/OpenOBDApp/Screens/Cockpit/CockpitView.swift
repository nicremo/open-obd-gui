import DiagnosticEngine
import OBDCore
import OpenOBDAppCore
import SwiftUI
import VehicleSim

struct CockpitView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.phase == .scanning {
            ScanProgressView()
        } else if let report = model.report {
            CockpitDashboard(report: report)
        } else {
            WelcomeView()
        }
    }
}

// MARK: - Dashboard

/// Direction "Zeitnahme": timing strip on top, then position tower, track map and messages.
/// The columns adapt to the width so no content forces a minimum window size.
struct CockpitDashboard: View {
    @Environment(AppModel.self) private var model
    let report: VehicleReport
    @State private var width: CGFloat = 1200
    @State private var selection: String?

    var body: some View {
        let markers = MapMarker.from(report: report)
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                header
                TimingStrip(report: report)
                if width >= 1380 {
                    // Very wide: tower, track map and messages side by side, the map keeps room for its callout columns.
                    HStack(alignment: .top, spacing: Spacing.xl) {
                        tower.frame(minWidth: 240, idealWidth: 300, maxWidth: 310)
                        map(markers).frame(minWidth: 620, maxWidth: .infinity)
                        feed.frame(minWidth: 260, idealWidth: 330, maxWidth: 340)
                    }
                } else if width >= 700 {
                    // The track map is the signature: it takes the width, tower and messages share the left column.
                    HStack(alignment: .top, spacing: Spacing.xl) {
                        VStack(alignment: .leading, spacing: Spacing.xl) {
                            tower
                            feed
                        }
                        .frame(minWidth: 240, idealWidth: 310, maxWidth: 320)
                        map(markers).frame(maxWidth: .infinity)
                    }
                } else {
                    map(markers)
                    tower
                    feed
                }
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.vertical, Spacing.l)
            .frame(maxWidth: 1800, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Palette.background)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(report.vehicle.title)
                .font(.obdHero)
                .foregroundStyle(Palette.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text(report.summary.headline)
                .font(.title3)
                .foregroundStyle(Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Spacing.m) {
                Text("\(report.meta.depth.german)-Scan, \(Fmt.date(report.meta.createdAt)), \(Fmt.number(Double(report.meta.durationMilliseconds) / 1000)) s")
                if model.reportSource == .archive {
                    Label("aus dem Verlauf", systemImage: "clock.arrow.circlepath").foregroundStyle(Palette.live)
                }
                if report.meta.simulated {
                    Label("Simulierte Daten, kein echtes Fahrzeug", systemImage: "testtube.2").foregroundStyle(Palette.unverifiedText)
                }
            }
            .font(.obdBody)
            .foregroundStyle(Palette.textSecondary)
            .lineLimit(1)
        }
    }

    private var tower: some View {
        PositionTower(report: report, selection: activeSelection) { select($0) }
    }

    private func map(_ markers: [MapMarker]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            FlagLegend()
            TrackMap(markers: markers, selection: activeSelection) { marker in select(marker.id) }
                .frame(height: 680)
        }
    }

    private var feed: some View {
        MessageFeed(report: report) { item in
            if let module = item.moduleID { selection = module }
            item.action(model)
        }
    }

    /// Tower and map mark the module the inspector shows, wherever it was opened from.
    private var activeSelection: String? {
        guard model.showInspector, let item = model.inspected else { return selection }
        switch item {
        case .troubleCode(let dtc): return report.module(for: dtc.module)?.id ?? selection
        case .module(let module): return module.id
        default: return selection
        }
    }

    /// One selection for tower and map. A module with faults opens its most urgent fault card.
    private func select(_ moduleID: String) {
        selection = moduleID
        guard let module = report.modules.first(where: { $0.id == moduleID }) else { return }
        if let group = FaultGroup.groups(from: report.faults(of: module.requestID)).first {
            model.inspect(.troubleCode(group.primary))
        } else {
            model.inspect(.module(module))
        }
    }
}

// MARK: - Timing strip

/// One strip with hairline dividers instead of key figure cards. Every segment has one click target.
struct TimingStrip: View {
    @Environment(AppModel.self) private var model
    let report: VehicleReport

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                if report.vehicleAnswered {
                    segment("Fehler", value: "\(report.summary.faultCount)", flag: Flag(report.worstSeverity),
                            note: report.worstSeverity.map { "höchste Stufe \($0.german)" } ?? "nichts gespeichert") { model.section = .faults }
                    segment("Dringend", value: "\(urgentCount)", flag: urgentCount > 0 ? Flag(.high) : nil,
                            note: "Hoch und Kritisch") { model.section = .faults }
                } else {
                    // Without any answer a zero would read as an all-clear.
                    segment("Fehler", value: nil, state: .noResponse, note: "nicht gelesen") { model.section = .faults }
                    segment("Dringend", value: nil, state: .noResponse, note: "nicht gelesen") { model.section = .faults }
                }
                segment("Steuergeräte", value: "\(report.summary.moduleCount)", note: busNote) { model.section = .modules }
                segment("Bordspannung", value: report.adapter.voltage.map { MeasuredValue.format($0, decimals: 1) }, unit: "V",
                        note: voltageNote, info: "Gemessen vom Adapter an Pin 16 der OBD-Buchse. Die Einordnung ist eine Faustregel für 12-V-Bleibatterien, keine Norm.") { model.section = .vehicle }
                segment("Bereitschaft", value: readinessValue, state: report.primaryReadiness == nil ? .noResponse : nil,
                        note: readinessNote) { model.section = .vehicle }
                segment("Motorleuchte", value: report.summary.milOn.map { $0 ? "an" : "aus" },
                        flag: report.summary.milOn.map { $0 ? .stop : .clear }, state: report.summary.milOn == nil ? .noResponse : nil,
                        note: "OBD Dienst 01, PID 01") { model.section = .faults }
                segment("Kilometer", value: report.odometer.map { MeasuredValue.format($0, decimals: 0) }, unit: "km",
                        state: odometerState, note: "PID A6") { model.section = .vehicle }
            }
        }
        .background(Palette.surface)
        .overlay(alignment: .top) { Rectangle().fill(Palette.hairline).frame(height: 1) }
        .overlay(alignment: .bottom) { Rectangle().fill(Palette.hairline).frame(height: 1) }
    }

    private func segment(_ label: String, value: String?, unit: String? = nil, flag: Flag? = nil, state: ValueState? = nil,
                         note: String, info: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.obdCaption).foregroundStyle(Palette.textSecondary)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if let flag { FlagGlyph(flag: flag, width: 16).alignmentGuide(.firstTextBaseline) { $0.height * 0.9 } }
                    if let state {
                        StateLabel(state: state, font: .timing(17, .semibold))
                    } else if let value {
                        Text(value).font(.timing(28, .bold)).foregroundStyle(Palette.textPrimary)
                        if let unit { Text(unit).font(.timing(15, .semibold)).foregroundStyle(Palette.textSecondary) }
                    } else {
                        StateLabel(state: .notRead, font: .timing(17, .semibold))
                    }
                }
                .frame(minHeight: 34, alignment: .leading)
                Text(note).font(.obdCaption).foregroundStyle(Palette.textTertiary).lineLimit(1)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, Spacing.m)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(info ?? "\(label) öffnen")
        .overlay(alignment: .trailing) { Rectangle().fill(Palette.hairline).frame(width: 1).padding(.vertical, Spacing.m) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(state?.word ?? value.map { "\($0) \(unit ?? "")" } ?? "nicht gelesen"), \(note)")
    }

    private var urgentCount: Int {
        FaultGroup.groups(from: report).filter { $0.severity >= .high }.count
    }

    private var busNote: String {
        let hs = report.modules.filter { $0.bus == .hsCAN }.count
        let ms = report.modules.filter { $0.bus == .msCAN }.count
        return "\(hs) HS-CAN, \(ms) MS-CAN"
    }

    private var voltageNote: String {
        guard let voltage = report.adapter.voltage else { return "nicht gemessen" }
        if report.findings.contains(where: { $0.kind == .noVehiclePower }) { return "kein Strom vom Auto" }
        if voltage >= 13.2 { return "Lichtmaschine lädt" }
        if voltage >= 12.2 { return "Batterie in Ordnung" }
        if voltage >= 11.8 { return "Batterie schwach" }
        return "Batterie sehr schwach"
    }

    private var readinessValue: String? {
        guard let readiness = report.primaryReadiness else { return nil }
        let supported = readiness.supportedMonitors.filter { !$0.continuous }
        return "\(supported.filter(\.complete).count)/\(supported.count)"
    }

    private var readinessNote: String {
        guard let readiness = report.primaryReadiness else { return "nicht gelesen" }
        if readiness.isReady { return "alle Tests abgeschlossen" }
        return readiness.incompleteMonitors.map(\.name).joined(separator: ", ") + " offen"
    }

    private var odometerState: ValueState? {
        guard report.odometer == nil else { return nil }
        let supported = report.obd.ecus.flatMap(\.supportedPIDs)
        if supported.isEmpty || report.snapshot.isEmpty { return .notRead }
        return supported.contains("A6") ? .noResponse : .unsupported
    }
}

// MARK: - Position tower

/// All control modules ranked by urgency, like the timing tower ranks the field.
struct PositionTower: View {
    let report: VehicleReport
    let selection: String?
    let onSelect: (String) -> Void
    @State private var hovered: String?

    var body: some View {
        let rows = ranked
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Steuergeräte nach Dringlichkeit").font(.obdTitle).foregroundStyle(Palette.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Text("\(rows.count)").font(.timing(13, .semibold)).foregroundStyle(Palette.textTertiary)
            }
            .padding(.bottom, Spacing.s)
            ForEach(Array(rows.enumerated()), id: \.element.module.id) { index, row in
                let selected = row.module.id == selection
                Button { onSelect(row.module.id) } label: {
                    HStack(spacing: Spacing.s) {
                        Text("\(index + 1)")
                            .font(.timing(12, .semibold))
                            .foregroundStyle(Palette.textTertiary)
                            .frame(width: 18, alignment: .trailing)
                        FlagGlyph(flag: Flag(row.severity))
                        Text(row.module.acronym ?? row.module.requestID)
                            .font(.obdCode)
                            .foregroundStyle(Palette.textPrimary)
                            .frame(width: 46, alignment: .leading)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(row.module.name).font(.obdLabel).foregroundStyle(Palette.textSecondary).lineLimit(1)
                            if let first = row.faults.first {
                                Text(first.primary.displayCode).font(.timing(12, .semibold)).foregroundStyle(Palette.textTertiary)
                            }
                        }
                        Spacer(minLength: 4)
                        Text(row.faults.isEmpty ? "frei" : (row.severity?.german ?? ""))
                            .font(.system(size: 12, weight: row.faults.isEmpty ? .regular : .medium))
                            .foregroundStyle(row.faults.isEmpty ? Palette.textSecondary : Palette.textPrimary)
                    }
                    .padding(.horizontal, Spacing.s)
                    .frame(minHeight: 40)
                    .background(selected ? Palette.selection : (hovered == row.module.id ? Palette.surfaceRaised : Color.clear),
                                in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovered = $0 ? row.module.id : nil }
                .accessibilityLabel("Platz \(index + 1), \(row.module.acronym ?? "") \(row.module.name), \(row.faults.isEmpty ? "frei" : "\(row.faults.count) Fehler, \(row.severity?.german ?? "")")")
            }
        }
    }

    struct Row {
        let module: ReportModule
        let faults: [FaultGroup]
        var severity: Severity? { faults.map(\.severity).max() }
    }

    private var ranked: [Row] {
        report.modules
            .map { Row(module: $0, faults: FaultGroup.groups(from: report.faults(of: $0.requestID))) }
            .sorted { lhs, rhs in
                let left = lhs.severity.map { $0.rankValue } ?? -1
                let right = rhs.severity.map { $0.rankValue } ?? -1
                if left != right { return left > right }
                if lhs.faults.count != rhs.faults.count { return lhs.faults.count > rhs.faults.count }
                return (lhs.module.acronym ?? lhs.module.requestID) < (rhs.module.acronym ?? rhs.module.requestID)
            }
    }
}

extension Severity {
    var rankValue: Int {
        switch self {
        case .info: 0
        case .medium: 1
        case .high: 2
        case .critical: 3
        }
    }
}

// MARK: - Messages

/// Timestamped messages like race control: faults and findings, most urgent first.
struct MessageFeed: View {
    struct Item: Identifiable {
        let id: String
        let flag: Flag
        let meta: String
        let code: String?
        let text: String
        let moduleID: String?
        let action: @MainActor (AppModel) -> Void
    }

    let report: VehicleReport
    let onOpen: (Item) -> Void

    var body: some View {
        let items = self.items
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Meldungen").font(.obdTitle).foregroundStyle(Palette.textPrimary).accessibilityAddTraits(.isHeader)
                Spacer()
                Text("\(items.count)").font(.timing(13, .semibold)).foregroundStyle(Palette.textTertiary)
            }
            .padding(.bottom, Spacing.s)
            if items.isEmpty {
                Text("Keine Meldungen. Kein Steuergerät meldet einen Fehler.")
                    .font(.obdBody)
                    .foregroundStyle(Palette.textSecondary)
                    .padding(.vertical, Spacing.m)
            }
            ForEach(items) { item in
                Button { onOpen(item) } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            FlagGlyph(flag: item.flag, width: 12)
                            Text(item.meta).font(.obdCaption).foregroundStyle(Palette.textSecondary).lineLimit(1)
                        }
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            if let code = item.code { DTCCodeText(displayCode: code, size: 14) }
                            Text(item.text).font(.obdBody).foregroundStyle(Palette.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.vertical, Spacing.s)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(alignment: .top) { Rectangle().fill(Palette.hairline).frame(height: 1) }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var items: [Item] {
        let time = Fmt.time(report.meta.createdAt)
        var result: [Item] = FaultGroup.groups(from: report).map { group in
            let module = report.module(for: group.module)
            return Item(id: "fault-\(group.id)", flag: Flag(group.severity),
                        meta: "\(time) · \(report.moduleLabel(for: group.module)) · \(group.primary.state)",
                        code: group.primary.displayCode, text: group.primary.title ?? "Keine Beschreibung hinterlegt",
                        moduleID: module?.id) { model in model.inspect(.troubleCode(group.primary)) }
        }
        for (index, finding) in report.findings.enumerated() where finding.kind != .simulated {
            result.append(Item(id: "finding-\(index)", flag: Flag(finding.severity), meta: "\(time) · \(finding.evidence)",
                               code: nil, text: finding.text, moduleID: nil) { model in
                model.section = finding.kind == .readinessIncomplete ? .vehicle : .faults
            })
        }
        return result
    }
}

/// What the flags and lines on the track map mean.
struct FlagLegend: View {
    var body: some View {
        // Two fixed rows, every entry keeps its words together.
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: Spacing.l) {
                entry(.clear, "frei")
                entry(.info, "Hinweis")
                entry(.caution, "Mittel")
                entry(.defect, "Hoch")
                entry(.stop, "Kritisch")
            }
            HStack(spacing: Spacing.l) {
                line(Palette.hsCAN, dashed: false, "HS-CAN 500 kbit/s")
                line(Palette.msCAN, dashed: true, "MS-CAN 125 kbit/s")
            }
        }
        .font(.obdCaption)
        .foregroundStyle(Palette.textSecondary)
    }

    private func entry(_ flag: Flag, _ text: String) -> some View {
        HStack(spacing: 5) {
            FlagGlyph(flag: flag, width: 12)
            Text(text)
        }
        .fixedSize()
        .help(flag.meaning)
    }

    private func line(_ color: Color, dashed: Bool, _ text: String) -> some View {
        HStack(spacing: 5) {
            Path { path in
                path.move(to: CGPoint(x: 0, y: 4))
                path.addLine(to: CGPoint(x: 22, y: 4))
            }
            .stroke(color, style: StrokeStyle(lineWidth: 2, dash: dashed ? [5, 4] : []))
            .frame(width: 22, height: 8)
            Text(text)
        }
        .fixedSize()
    }
}

// MARK: - Welcome

/// Before the first scan: the three steps as one strip, then the connection choice as a native list.
struct WelcomeView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Bereit zum Auslesen").font(.obdHero).foregroundStyle(Palette.textPrimary).accessibilityAddTraits(.isHeader)
                    Text("Open OBD GUI liest nur. Am Fahrzeug wird nichts verändert.").font(.obdBody).foregroundStyle(Palette.textSecondary)
                }
                if case .failed(let message) = model.phase {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.obdBody)
                        .foregroundStyle(Palette.fault)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 0) {
                    step(1, "Adapter einstecken", "OBDLink EX in die OBD-Buchse unter dem Lenkrad, USB an den Mac.")
                    step(2, "Zündung an", "Der Motor darf laufen, muss aber nicht.")
                    step(3, "Auslesen", "Standard dauert am Fahrzeug etwa eine Minute.")
                }
                .background(Palette.surface)
                .overlay(alignment: .top) { Rectangle().fill(Palette.hairline).frame(height: 1) }
                .overlay(alignment: .bottom) { Rectangle().fill(Palette.hairline).frame(height: 1) }

                VStack(alignment: .leading, spacing: Spacing.m) {
                    Text("Verbindung").font(.obdTitle).foregroundStyle(Palette.textPrimary).accessibilityAddTraits(.isHeader)
                    Picker("Verbindung", selection: Binding(get: { model.choice }, set: { choice in Task { await model.select(choice) } })) {
                        Text("\(ConnectionChoice.automatic.title): \(adapterDetail)").tag(ConnectionChoice.automatic)
                        ForEach(VehicleProfile.all) { profile in
                            Text("Simulator \(profile.title): \(profile.note)").tag(ConnectionChoice.simulator(profile.id))
                        }
                    }
                    .pickerStyle(.radioGroup)
                    .labelsHidden()
                    HStack(spacing: Spacing.m) {
                        Picker("Tiefe", selection: Binding(get: { model.depth }, set: { model.depth = $0 })) {
                            ForEach(ScanDepth.allCases, id: \.self) { Text($0.german).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .fixedSize()
                        Text(model.depth.explanation).font(.obdCaption).foregroundStyle(Palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: Spacing.s)
                        Button {
                            Task { await model.scan() }
                        } label: {
                            Label("Auslesen", systemImage: "play.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(model.isOccupied)
                    }
                }
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.vertical, Spacing.l)
            .frame(maxWidth: 1100, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Palette.background)
    }

    private func step(_ number: Int, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: Spacing.m) {
            Text("\(number)").font(.timing(30, .heavy)).foregroundStyle(Palette.textTertiary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.obdHeadline).foregroundStyle(Palette.textPrimary)
                Text(text).font(.obdBody).foregroundStyle(Palette.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Spacing.l)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .overlay(alignment: .trailing) { Rectangle().fill(Palette.hairline).frame(width: 1).padding(.vertical, Spacing.m) }
    }

    private var adapterDetail: String {
        if let best = model.candidates.first(where: \.isLikelyOBDAdapter) {
            return "gefunden, \(best.productName ?? best.path)"
        }
        return "kein Adapter erkannt"
    }
}

// MARK: - Scan progress

struct ScanProgressView: View {
    @Environment(AppModel.self) private var model
    @State private var width: CGFloat = 1200

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Fahrzeug wird ausgelesen").font(.obdHero).foregroundStyle(Palette.textPrimary)
                    Text("Zündung an lassen, Adapter nicht abziehen. Tiefe: \(model.depth.german).").font(.obdBody).foregroundStyle(Palette.textSecondary)
                }
                ProgressView(value: progress).tint(Palette.live)
                let layout = width >= 760 ? AnyLayout(HStackLayout(alignment: .top, spacing: Spacing.xl)) : AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.xl))
                layout {
                    VStack(alignment: .leading, spacing: Spacing.m) {
                        ForEach(model.steps) { step in StepRow(progress: step) }
                    }
                    .frame(minWidth: 220, idealWidth: 360, maxWidth: 420, alignment: .leading)
                    VStack(alignment: .leading, spacing: Spacing.s) {
                        Text("\(model.foundModules.count) Steuergeräte gefunden").font(.obdTitle).foregroundStyle(Palette.textPrimary)
                        TrackMap(markers: MapMarker.from(found: model.foundModules))
                            .frame(minHeight: 520)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.vertical, Spacing.l)
        }
        .background(Palette.background)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }

    private var progress: Double {
        guard !model.steps.isEmpty else { return 0 }
        let finished = model.steps.filter {
            switch $0.state {
            case .pending, .running: false
            default: true
            }
        }.count
        return Double(finished) / Double(model.steps.count)
    }
}

struct StepRow: View {
    let progress: StepProgress

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.m) {
            icon.frame(width: 18, height: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(progress.step.title).font(.obdBody).foregroundStyle(titleColor)
                if let detail {
                    Text(detail).font(.obdCaption).foregroundStyle(Palette.textSecondary)
                }
            }
            Spacer()
        }
    }

    @ViewBuilder private var icon: some View {
        switch progress.state {
        case .pending: Image(systemName: "circle.dashed").foregroundStyle(Palette.textTertiary)
        case .running: ProgressView().controlSize(.small)
        case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.ok)
        case .skipped: Image(systemName: "minus.circle").foregroundStyle(Palette.textTertiary)
        case .failed: Image(systemName: "xmark.octagon.fill").foregroundStyle(Palette.fault)
        }
    }

    private var titleColor: Color {
        if case .pending = progress.state { return Palette.textTertiary }
        return Palette.textPrimary
    }

    private var detail: String? {
        switch progress.state {
        case .done(let text), .skipped(let text), .failed(let text): text.isEmpty ? nil : text
        default: nil
        }
    }
}
