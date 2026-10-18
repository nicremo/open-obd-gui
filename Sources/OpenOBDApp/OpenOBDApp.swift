import OpenOBDAppCore
import SwiftUI

@main
struct OpenOBDApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup("Open OBD GUI") {
            RootView()
                .environment(model)
                .frame(minWidth: 1280, maxWidth: .infinity, minHeight: 700, maxHeight: .infinity)
                .task { await LaunchActions.run(model) }
        }
        .defaultSize(width: 1500, height: 940)
        .windowToolbarStyle(.unified)
        .commands {
            CommandMenu("Fahrzeug") {
                Button("Fahrzeug auslesen") { Task { await model.scan() } }
                    .keyboardShortcut("r", modifiers: .command)
                    .disabled(model.isOccupied)
                Button("Verbinden") { Task { await model.connect() } }
                    .keyboardShortcut("k", modifiers: [.command, .shift])
                    .disabled(model.isOccupied)
                Button("Trennen") { Task { await model.disconnect() } }
                    .disabled(model.adapter == nil)
                Divider()
                Button(model.phase == .live ? "Live-Daten pausieren" : "Live-Daten starten") { Task { await model.toggleLive() } }
                    .disabled(model.isOccupied)
                Divider()
                Button("Bericht als JSON sichern …") { model.report.map { ReportExport.save($0, as: .json) } }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                    .disabled(model.report == nil)
                Button("Bericht als Markdown sichern …") { model.report.map { ReportExport.save($0, as: .markdown) } }
                    .disabled(model.report == nil)
                Divider()
                Button("Technik-Inspector") { model.showInspector.toggle() }
                    .keyboardShortcut("i", modifiers: [.command, .option])
            }
            CommandGroup(after: .sidebar) {
                ForEach(Array(AppSection.allCases.enumerated()), id: \.element) { index, section in
                    Button(section.title) { model.section = section }
                        .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
                }
            }
        }
    }
}
