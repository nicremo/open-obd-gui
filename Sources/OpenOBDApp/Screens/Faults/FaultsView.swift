import DiagnosticEngine
import OBDCore
import OpenOBDAppCore
import SwiftUI

enum FaultFilter: String, CaseIterable {
    case all, urgent, active

    func matches(_ group: FaultGroup) -> Bool {
        switch self {
        case .all: true
        case .urgent: group.severity >= .high
        case .active: group.isActive
        }
    }
}

/// Grouped by module, most urgent first, explanation on click, raw data in the inspector.
struct FaultsView: View {
    @Environment(AppModel.self) private var model
    @SceneStorage("faults.filter") private var filterRaw = FaultFilter.all.rawValue
    @SceneStorage("faults.query") private var query = ""
    @State private var expanded: Set<String> = []
    @State private var width: CGFloat = 1200

    var body: some View {
        if let report = model.report {
            content(report)
        } else {
            NoReportView(section: .faults)
        }
    }

    private func content(_ report: VehicleReport) -> some View {
        let all = FaultGroup.groups(from: report)
        let filter = FaultFilter(rawValue: filterRaw) ?? .all
        let visible = all.filter { filter.matches($0) && matchesQuery($0) }
        let modules = orderedModules(visible)
        return ScreenScaffold(title: "Fehlerspeicher", subtitle: report.summary.headline) {
            FilterChipBar(options: [
                (FaultFilter.all, "Alle", all.count),
                (FaultFilter.urgent, "Dringend", all.filter { FaultFilter.urgent.matches($0) }.count),
                (FaultFilter.active, "Aktiv", all.filter { FaultFilter.active.matches($0) }.count),
            ], selection: Binding(get: { filter }, set: { filterRaw = $0.rawValue }))
        } content: {
            if all.isEmpty, !report.vehicleAnswered {
                EmptyState(symbol: "antenna.radiowaves.left.and.right.slash", title: "Fehlerspeicher nicht gelesen",
                           message: report.silenceReason)
            } else if all.isEmpty {
                EmptyState(symbol: "checkmark.seal", title: "Kein Steuergerät meldet einen Fehler",
                           message: "Geprüft wurden \(report.modules.count) Steuergeräte und die OBD-Abgasdiagnose von \(report.obd.ecus.count) Steuergeräten.",
                           tint: Palette.ok)
            } else if visible.isEmpty {
                EmptyState(symbol: "line.3.horizontal.decrease.circle", title: "Keine Treffer",
                           message: "Kein Fehler passt zu diesem Filter oder Suchbegriff.")
            } else {
                ForEach(modules, id: \.self) { address in
                    let groups = visible.filter { $0.module == address }
                    Panel(title: report.moduleLabel(for: address), subtitle: moduleSubtitle(address, report: report)) {
                        Text(groups.count == 1 ? "1 Fehler" : "\(groups.count) Fehler")
                            .font(.obdLabel)
                            .foregroundStyle(Palette.textSecondary)
                    } content: {
                        VStack(spacing: 0) {
                            ForEach(groups) { group in
                                FaultRow(group: group, expanded: expanded.contains(group.id), inspected: isInspected(group), compact: width < 700) {
                                    toggle(group.id)
                                } onInspect: {
                                    model.inspect(.troubleCode(group.primary))
                                }
                                if group.id != groups.last?.id { Divider() }
                            }
                        }
                    }
                }
            }
        }
        .searchable(text: $query, placement: .toolbar, prompt: "Code oder Beschreibung")
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }

    private func matchesQuery(_ group: FaultGroup) -> Bool {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return true }
        let haystack = [group.primary.displayCode, group.primary.title ?? "", group.primary.system, group.module].joined(separator: " ")
        return haystack.localizedCaseInsensitiveContains(text)
    }

    private func orderedModules(_ groups: [FaultGroup]) -> [String] {
        var order: [String] = []
        for group in groups where !order.contains(group.module) {
            order.append(group.module)
        }
        return order
    }

    private func moduleSubtitle(_ address: String, report: VehicleReport) -> String {
        if let module = report.module(for: address) {
            return "\(module.bus.shortName) · Anfrage \(module.requestID) · Antwort \(module.responseID)"
        }
        return "OBD-Abgasdiagnose · Anfrage \(address)"
    }

    private func isInspected(_ group: FaultGroup) -> Bool {
        guard model.showInspector, case .troubleCode(let dtc)? = model.inspected else { return false }
        return group.entries.contains { $0.id == dtc.id }
    }

    private func toggle(_ id: String) {
        if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
    }
}

struct FaultRow: View {
    let group: FaultGroup
    let expanded: Bool
    var inspected = false
    var compact = false
    let onToggle: () -> Void
    let onInspect: () -> Void

    var body: some View {
        let dtc = group.primary
        VStack(alignment: .leading, spacing: Spacing.m) {
            if !compact {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.m) {
                    SeverityBadge(severity: group.severity)
                        .frame(width: 92, alignment: .leading)
                    DTCCodeText(displayCode: dtc.displayCode)
                        .frame(width: 100, alignment: .leading)
                    titleBlock(dtc)
                    Spacer(minLength: Spacing.s)
                    trailing(dtc)
                }
            } else {
                // Narrow column: code line on top, the title gets the full width below.
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    HStack(alignment: .firstTextBaseline, spacing: Spacing.m) {
                        SeverityBadge(severity: group.severity)
                        DTCCodeText(displayCode: dtc.displayCode)
                        Spacer(minLength: Spacing.s)
                        trailing(dtc)
                    }
                    titleBlock(dtc)
                }
            }
            if expanded {
                FaultExplanation(group: group, onInspect: onInspect)
                    .padding(.leading, Spacing.l)
            }
        }
        .padding(.vertical, Spacing.m)
        .padding(.horizontal, Spacing.s)
        .background(inspected ? Palette.selection : Color.clear, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture(perform: onToggle)
        .onTapGesture(count: 2, perform: onInspect)
        .contextMenu {
            Button("Technik anzeigen", action: onInspect)
            Button("Code kopieren") { copyToPasteboard(dtc.displayCode) }
            Button("Code und Beschreibung kopieren") { copyToPasteboard("\(dtc.displayCode) \(dtc.title ?? "")") }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(dtc.displayCode), \(dtc.title ?? "keine Beschreibung"), Dringlichkeit \(group.severity.german), \(dtc.state)")
        .accessibilityAction(named: "Technik anzeigen", onInspect)
    }

    private func titleBlock(_ dtc: ReportDTC) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(dtc.title ?? "Keine Beschreibung hinterlegt")
                .font(.obdBody)
                .foregroundStyle(dtc.title == nil ? Palette.textSecondary : Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text([dtc.system, dtc.origin, sourceText].joined(separator: " · "))
                .font(.obdCaption)
                .foregroundStyle(Palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func trailing(_ dtc: ReportDTC) -> some View {
        HStack(spacing: Spacing.m) {
            StateChip(state: group.isActive ? "aktiv" : dtc.state)
            Image(systemName: "chevron.right")
                .font(.obdCaption)
                .foregroundStyle(Palette.textTertiary)
                .rotationEffect(.degrees(expanded ? 90 : 0))
        }
        .fixedSize()
    }

    private var sourceText: String {
        let sources = Set(group.sources.map { $0 == .uds ? "Steuergerät" : "OBD" })
        return sources.sorted().joined(separator: " und ")
    }
}

/// Plain language part of a fault: what it means, urgency, causes, why this severity.
struct FaultExplanation: View {
    let group: FaultGroup
    let onInspect: () -> Void

    var body: some View {
        let dtc = group.primary
        VStack(alignment: .leading, spacing: Spacing.m) {
            if let explanation = dtc.explanation {
                ExplanationBlock(title: "Was bedeutet das?", text: explanation.what)
                ExplanationBlock(title: "Wie dringend? Einschätzung der Wissensbasis", text: explanation.urgency)
                if !explanation.causes.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Mögliche Ursachen").font(.obdLabel).foregroundStyle(Palette.textSecondary)
                        ForEach(explanation.causes, id: \.self) { cause in
                            Label(cause, systemImage: "smallcircle.filled.circle")
                                .font(.obdBody)
                                .foregroundStyle(Palette.textPrimary)
                                .labelStyle(BulletLabelStyle())
                        }
                    }
                }
                HStack(spacing: Spacing.s) {
                    ConfidenceBadge(confidence: explanation.confidence)
                    Text("Quelle: \(explanation.source)").font(.obdCaption).foregroundStyle(Palette.textTertiary)
                }
            } else {
                Text("Für diesen Code ist keine geprüfte Erklärung hinterlegt. Die Rohdaten stehen im Inspector.")
                    .font(.obdBody)
                    .foregroundStyle(Palette.textSecondary)
            }
            if let category = dtc.failureTypeCategory {
                ExplanationBlock(title: "Fehlerart \(dtc.failureType ?? "")", text: [category, dtc.failureTypeDetail].compactMap { $0 }.joined(separator: ": "))
            }
            if !dtc.severityReasons.isEmpty {
                ExplanationBlock(title: "Warum \(dtc.severity.german)?", text: dtc.severityReasons.joined(separator: " "))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Gemeldet von").font(.obdLabel).foregroundStyle(Palette.textSecondary)
                ForEach(group.entries) { entry in
                    HStack(spacing: Spacing.s) {
                        Text(entry.source.german).font(.obdBody)
                        StateChip(state: entry.state)
                    }
                }
            }
            Button("Rohdaten im Inspector", systemImage: "sidebar.trailing", action: onInspect)
                .buttonStyle(.link)
        }
    }
}

struct ExplanationBlock: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.obdLabel).foregroundStyle(Palette.textSecondary)
            Text(text).font(.obdBody).foregroundStyle(Palette.textPrimary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct BulletLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("•").foregroundStyle(Palette.textTertiary)
            configuration.title
        }
    }
}

/// One line per fault for the cockpit.
struct CompactFaultRow: View {
    let group: FaultGroup
    let moduleLabel: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.m) {
            DTCCodeText(displayCode: group.primary.displayCode)
                .frame(width: 100, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text(group.primary.title ?? "Keine Beschreibung hinterlegt")
                    .font(.obdBody)
                    .foregroundStyle(group.primary.title == nil ? Palette.textSecondary : Palette.textPrimary)
                    .lineLimit(1)
                Text(moduleLabel).font(.obdCaption).foregroundStyle(Palette.textTertiary).lineLimit(1)
            }
            Spacer(minLength: Spacing.s)
            SeverityBadge(severity: group.severity)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}
