import AppKit
import DiagnosticEngine
import OpenOBDAppCore
import SwiftUI

/// Saved reports, newest first. Opening loads the report into the cockpit with the archive band.
struct HistoryView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScreenScaffold(title: "Verlauf", subtitle: "\(model.archive.count) gespeicherte Berichte · jeder Scan wird automatisch gesichert") {
            Button("Aktualisieren", systemImage: "arrow.clockwise") { model.refreshArchive() }
        } content: {
            if model.archive.isEmpty {
                EmptyState(symbol: "clock.arrow.circlepath", title: "Noch keine Berichte",
                           message: "Nach jedem Scan sichert die App einen Bericht. Hier kannst du ihn später öffnen und vergleichen.")
            } else {
                Panel(title: "Berichte", padding: Spacing.m) {
                    VStack(spacing: 0) {
                        ForEach(model.archive) { entry in
                            HistoryRow(entry: entry) { model.open(entry) }
                            if entry.id != model.archive.last?.id { Divider() }
                        }
                    }
                }
            }
        }
    }
}

struct HistoryRow: View {
    let entry: ReportStore.Entry
    let onOpen: () -> Void

    var body: some View {
        HStack(spacing: Spacing.m) {
            Image(systemName: entry.simulated ? "testtube.2" : "car.side")
                .font(.system(size: 18))
                .foregroundStyle(entry.simulated ? Palette.unverified : Palette.textSecondary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Spacing.s) {
                    Text(entry.title).font(.obdHeadline).foregroundStyle(Palette.textPrimary)
                    if entry.simulated { Chip(text: "Simulator", color: Palette.unverified) }
                }
                Text(entry.headline).font(.obdBody).foregroundStyle(Palette.textSecondary).lineLimit(1)
                HStack(spacing: Spacing.s) {
                    Text(Fmt.date(entry.date))
                    if let vin = entry.vin { Text(vin).font(.obdMono) }
                }
                .font(.obdCaption)
                .foregroundStyle(Palette.textTertiary)
            }
            Spacer()
            if entry.faultCount > 0 {
                HStack(spacing: 6) {
                    FlagGlyph(flag: .caution)
                    Text(entry.faultCount == 1 ? "1 Fehler" : "\(entry.faultCount) Fehler").font(.system(size: 12)).foregroundStyle(Palette.textPrimary)
                }
                .help("Fehler im gespeicherten Bericht")
            } else {
                HStack(spacing: 6) {
                    FlagGlyph(flag: .clear)
                    Text("keine Fehler").font(.system(size: 12)).foregroundStyle(Palette.textSecondary)
                }
            }
            Button("Öffnen", action: onOpen)
        }
        .padding(.vertical, Spacing.s)
        .padding(.horizontal, Spacing.xs)
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: onOpen)
        .contextMenu {
            Button("Öffnen", action: onOpen)
            Button("Im Finder zeigen") { NSWorkspace.shared.activateFileViewerSelecting([entry.url]) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: "Öffnen", onOpen)
    }
}
