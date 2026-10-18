import AppKit
import OpenOBDAppCore
import SwiftUI

/// Shown in every section that needs a report.
struct NoReportView: View {
    @Environment(AppModel.self) private var model
    let section: AppSection

    var body: some View {
        ScreenScaffold(title: section.title) {
            VStack(spacing: Spacing.l) {
                EmptyState(symbol: section.symbol, title: "Noch nicht ausgelesen",
                           message: "Verbinde den Adapter, schalte die Zündung ein und lies das Fahrzeug aus. Alte Berichte findest du im Verlauf.")
                HStack {
                    Button("Fahrzeug auslesen", systemImage: "play.fill") { Task { await model.scan() } }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.isOccupied)
                    Button("Verlauf öffnen") { model.section = .history }
                }
            }
        }
    }
}

@MainActor
func copyToPasteboard(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
}
