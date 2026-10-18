import DiagnosticEngine
import OpenOBDAppCore
import VehicleSim
import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @State private var columns: NavigationSplitViewVisibility = .all
    @State private var windowWidth: CGFloat = 1500
    @State private var collapsedForInspector = false

    /// Below this width sidebar, content and inspector do not fit side by side.
    private static let threeColumnWidth: CGFloat = 1400

    var body: some View {
        @Bindable var model = model
        NavigationSplitView(columnVisibility: $columns) {
            Sidebar()
                .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 280)
        } detail: {
            // The geometry reader reports no minimum of its own, so no screen can push its content minimum
            // into the split view. Content-derived minimums made the split view re-measure endlessly and,
            // with the inspector open, overflow the window.
            GeometryReader { _ in
                detail.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
                .frame(minWidth: 420, maxWidth: .infinity, minHeight: 360, maxHeight: .infinity)
                .clipped()
                .background(Palette.background)
                .toolbar { MainToolbar(model: model) }
        }
        // The inspector belongs to the whole window, as in Xcode. Attached to the detail column it nested a
        // second split view whose minimum jumped when it opened, and the outer split view never settled.
        .inspector(isPresented: $model.showInspector) {
            GeometryReader { _ in
                InspectorView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
                .inspectorColumnWidth(min: 300, ideal: 360, max: 440)
        }
        .navigationTitle(model.section.title)
        .navigationSubtitle(model.agentActivity.map { "Agent: \($0)" } ?? "")
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
            windowWidth = width
            fitColumns()
        }
        .onChange(of: model.showInspector) { _, _ in fitColumns() }
    }

    /// In a narrow window the inspector takes the sidebar's place, as in Xcode, instead of squeezing three
    /// columns: macOS then laid the columns out wider than the window. The sidebar returns with the inspector closed.
    private func fitColumns() {
        if model.showInspector && windowWidth < Self.threeColumnWidth {
            if columns != .detailOnly {
                columns = .detailOnly
                collapsedForInspector = true
            }
        } else if collapsedForInspector {
            columns = .all
            collapsedForInspector = false
        }
    }

    @ViewBuilder private var detail: some View {
        switch model.section {
        case .cockpit: CockpitView()
        case .faults: FaultsView()
        case .live: LiveView()
        case .modules: ModulesView()
        case .vehicle: VehicleView()
        case .history: HistoryView()
        case .workshop: WorkshopView()
        }
    }
}

/// Lean toolbar: read with the depth as a menu, export, inspector. The connection lives in the sidebar.
/// Wide items here made the window grow on its own once the inspector opened in a narrow window.
struct MainToolbar: ToolbarContent {
    let model: AppModel

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Menu {
                Picker("Tiefe", selection: Binding(get: { model.depth }, set: { model.depth = $0 })) {
                    ForEach(ScanDepth.allCases, id: \.self) { depth in
                        Text("\(depth.german): \(depth.explanation)").tag(depth)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                Label("Auslesen (\(model.depth.german))", systemImage: "play.fill")
            } primaryAction: {
                Task { await model.scan() }
            }
            .menuStyle(.button)
            .disabled(model.isOccupied)
            .help("Fahrzeug auslesen (⌘R). Pfeil wählt die Tiefe, im Moment \(model.depth.german).")

            ExportMenu(model: model)

            Button {
                model.showInspector.toggle()
            } label: {
                Label("Technik", systemImage: "sidebar.trailing")
            }
            .help("Technik-Inspector ein- oder ausblenden (⌥⌘I)")
        }
    }
}

/// Connection state in the toolbar: colored dot, short text, choice menu.
struct ConnectionPill: View {
    let model: AppModel

    var body: some View {
        Menu {
            ConnectionMenuItems(model: model)
        } label: {
            HStack(spacing: 6) {
                Circle().fill(PhaseStyle.color(model.phase, connected: model.adapter != nil)).frame(width: 8, height: 8)
                Text(PhaseStyle.short(model.phase, connected: model.adapter != nil))
            }
        }
        .menuStyle(.button)
        .fixedSize()
        .help(model.statusLine)
    }
}

struct ConnectionMenuItems: View {
    let model: AppModel

    var body: some View {
        Section("Verbindung") {
            choiceButton(.automatic)
            ForEach(model.candidates, id: \.path) { candidate in
                choiceButton(.port(candidate.path), detail: candidate.productName)
            }
        }
        Section("Simulator (ohne Fahrzeug)") {
            ForEach(VehicleProfile.all) { profile in
                choiceButton(.simulator(profile.id))
            }
        }
        Divider()
        Button("Adapter neu suchen") { model.refreshDevices() }
        Button("Verbinden") { Task { await model.connect() } }
            .disabled(model.isOccupied)
        Button("Trennen") { Task { await model.disconnect() } }
            .disabled(model.adapter == nil)
    }

    private func choiceButton(_ choice: ConnectionChoice, detail: String? = nil) -> some View {
        Button {
            Task { await model.select(choice) }
        } label: {
            if model.choice == choice {
                Label(detail.map { "\(choice.title) (\($0))" } ?? choice.title, systemImage: "checkmark")
            } else {
                Text(detail.map { "\(choice.title) (\($0))" } ?? choice.title)
            }
        }
    }
}

enum PhaseStyle {
    static func color(_ phase: AppModel.Phase, connected: Bool) -> Color {
        switch phase {
        case .idle: connected ? Palette.ok : Palette.textTertiary
        case .connecting, .scanning: Palette.live
        case .connected: Palette.ok
        case .live: Palette.live
        case .failed: Palette.fault
        }
    }

    static func short(_ phase: AppModel.Phase, connected: Bool) -> String {
        switch phase {
        case .idle: connected ? "Verbunden" : "Nicht verbunden"
        case .connecting: "Verbinde"
        case .connected: "Verbunden"
        case .scanning: "Liest aus"
        case .live: "Live"
        case .failed: "Fehler"
        }
    }
}
