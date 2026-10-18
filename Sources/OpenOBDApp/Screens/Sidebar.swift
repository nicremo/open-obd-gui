import DiagnosticEngine
import OpenOBDAppCore
import SwiftUI

/// Native sidebar with room to breathe: a typographic vehicle head, the seven sections with
/// equal icon widths and plain counts, the connection at the bottom behind a hairline.
struct Sidebar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        List(selection: $model.section) {
            VehicleHeader()
                .listRowInsets(EdgeInsets(top: Spacing.s, leading: Spacing.m, bottom: Spacing.l, trailing: Spacing.m))
                .selectionDisabled()
            Section("Diagnose") {
                ForEach(AppSection.allCases) { section in
                    Label(section.title, systemImage: section.symbol)
                        .badge(badge(for: section))
                        .tag(section)
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ConnectionFooter()
        }
    }
}

extension Sidebar {
    /// Native sidebar badges: macOS draws them as plain numbers at the trailing edge.
    func badge(for section: AppSection) -> Text? {
        switch section {
        case .faults: model.report.flatMap { $0.summary.faultCount > 0 ? Text("\($0.summary.faultCount)") : nil }
        case .modules: model.report.flatMap { $0.modules.isEmpty ? nil : Text("\($0.modules.count)") }
        case .history: model.archive.isEmpty ? nil : Text("\(model.archive.count)")
        case .live: model.phase == .live ? Text("Live") : nil
        default: nil
        }
    }
}

/// Vehicle name, the worst flag with the count and the VIN, in system type. No icon box.
struct VehicleHeader: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(model.report?.vehicle.title ?? "Kein Fahrzeug")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            if let report = model.report {
                HStack(spacing: 6) {
                    FlagGlyph(flag: Flag(report.worstSeverity), width: 13)
                    Text(status(report))
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.textSecondary)
                }
                Text(report.vehicle.vin ?? "FIN nicht gelesen")
                    .font(.timing(12, .medium))
                    .tracking(0.4)
                    .foregroundStyle(Palette.textTertiary)
                    .lineLimit(1)
                    .textSelection(.enabled)
            } else {
                Text("Noch nicht ausgelesen")
                    .font(.obdCaption)
                    .foregroundStyle(Palette.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func status(_ report: VehicleReport) -> String {
        let count = report.summary.faultCount
        guard count > 0 else { return "Keine Fehler" }
        let urgent = FaultGroup.groups(from: report).filter { $0.severity >= .high }.count
        let faults = count == 1 ? "1 Fehler" : "\(count) Fehler"
        return urgent > 0 ? "\(faults) · \(urgent) dringend" : faults
    }
}

/// Count as plain tabular figures, used next to list rows.
struct CountBadge: View {
    let count: Int
    let color: Color

    var body: some View {
        Text("\(count)")
            .font(.timing(13, .bold))
            .foregroundStyle(color)
    }
}

/// Connection status at the bottom of the sidebar, separated by a hairline, no box.
struct ConnectionFooter: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Circle()
                    .fill(PhaseStyle.color(model.phase, connected: model.adapter != nil))
                    .frame(width: 7, height: 7)
                Text(PhaseStyle.short(model.phase, connected: model.adapter != nil))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Palette.textPrimary)
                Spacer()
                if model.isOccupied {
                    ProgressView().controlSize(.mini)
                }
            }
            Text(model.adapter.map { "\($0.identity.displayName)\($0.voltage.map { " · \(Fmt.number($0)) V" } ?? "")" } ?? model.choice.title)
                .font(.obdCaption)
                .foregroundStyle(Palette.textSecondary)
                .lineLimit(2)
            if let activity = model.agentActivity {
                Label("Agent: \(activity)", systemImage: "terminal")
                    .font(.obdCaption)
                    .foregroundStyle(Palette.live)
                    .lineLimit(2)
                    .help("Ein Agent liest gerade über die App. Der Verkehr steht in der Werkstatt.")
            }
            Menu {
                ConnectionMenuItems(model: model)
            } label: {
                Text("Verbindung ändern")
            }
            .menuStyle(.borderlessButton)
            .font(.obdCaption)
            .fixedSize()
            .foregroundStyle(Palette.live)
        }
        .padding(.horizontal, Spacing.l)
        .padding(.vertical, Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { Rectangle().fill(Palette.hairline).frame(height: 1) }
    }
}
