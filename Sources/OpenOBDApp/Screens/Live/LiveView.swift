import DiagnosticEngine
import OBDCore
import OpenOBDAppCore
import SwiftUI

/// Gauges for the key values, one chart with axes, then the list of all polled values.
struct LiveView: View {
    @Environment(AppModel.self) private var model
    @State private var showPicker = false

    static let gaugePIDs: [UInt8] = [0x0C, 0x0D, 0x05, 0x42]

    var body: some View {
        ScreenScaffold(title: "Live-Daten", subtitle: subtitle) {
            controls
        } content: {
            if model.liveSeries.isEmpty {
                emptyState
            } else {
                gauges
                if let selected = selectedSeries {
                    Panel(title: selected.name, subtitle: "Steuergerät \(selected.ecu) · Verlauf der letzten \(windowText)") {
                        ConfidenceBadge(confidence: selected.latest?.definition.confidence ?? .unknown)
                    } content: {
                        LiveChart(series: selected, window: model.liveWindow, maximumGap: gapLimit)
                            .frame(height: 220)
                    }
                }
                Panel(title: "Alle Werte", subtitle: "\(model.liveSeries.count) Messwerte · Min, Max und Mittel seit Start") {
                    Button("Zurücksetzen") { model.clearLive() }
                        .buttonStyle(.link)
                        .disabled(model.phase == .live)
                } content: {
                    ValueTable(series: model.liveSeries, selectedID: model.selectedSeriesID ?? model.liveSeries.first?.id, dimmed: model.phase != .live) { series in
                        model.selectedSeriesID = series.id
                    } onInspect: { series in
                        if let latest = series.latest { model.inspect(.measurement(latest)) }
                    }
                }
            }
        }
    }

    private var subtitle: String {
        switch model.phase {
        case .live: return "Live · alle \(model.liveInterval) ms · \(model.livePIDs.count) Werte"
        default:
            if let last = model.lastLiveUpdate { return "Pausiert · zuletzt \(Fmt.time(last))" }
            return model.adapter == nil ? "Nicht verbunden" : "Bereit"
        }
    }

    private var windowText: String {
        model.liveWindow >= 60 ? "\(Int(model.liveWindow / 60)) min" : "\(Int(model.liveWindow)) s"
    }

    /// A gap is drawn when a value did not arrive for three cycles.
    private var gapLimit: TimeInterval {
        max(1.5, Double(model.liveInterval) / 1000 * 3 + Double(model.livePIDs.count) * 0.15)
    }

    private var selectedSeries: LiveSeries? {
        model.liveSeries.first { $0.id == model.selectedSeriesID } ?? model.liveSeries.first
    }

    private var controls: some View {
        HStack(spacing: Spacing.m) {
            HStack(spacing: 6) {
                LiveDot(active: model.phase == .live)
                Text(model.phase == .live ? "Live" : "Pausiert").font(.obdLabel).foregroundStyle(Palette.textSecondary)
                    .lineLimit(1)
                    .fixedSize()
            }
            Picker("Zeitfenster", selection: Binding(get: { model.liveWindow }, set: { model.liveWindow = $0 })) {
                Text("30 s").tag(TimeInterval(30))
                Text("1 min").tag(TimeInterval(60))
                Text("5 min").tag(TimeInterval(300))
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 170)
            Menu {
                ForEach([100, 300, 500, 1000], id: \.self) { interval in
                    Button {
                        model.liveInterval = interval
                        Task { await model.setLivePIDs(model.livePIDs) }
                    } label: {
                        if model.liveInterval == interval {
                            Label("\(interval) ms", systemImage: "checkmark")
                        } else {
                            Text("\(interval) ms")
                        }
                    }
                }
            } label: {
                Label("\(model.liveInterval) ms", systemImage: "timer")
            }
            .fixedSize()
            .help("Pause zwischen zwei Abfragerunden")
            Button {
                showPicker = true
            } label: {
                Label("Werte wählen", systemImage: "slider.horizontal.3")
            }
            .popover(isPresented: $showPicker, arrowEdge: .bottom) {
                PIDPicker()
                    .frame(width: 380, height: 480)
            }
            Button {
                Task { await model.toggleLive() }
            } label: {
                Label(model.phase == .live ? "Pausieren" : "Starten", systemImage: model.phase == .live ? "pause.fill" : "play.fill")
                    .frame(minWidth: 84)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.space, modifiers: [])
            .disabled(model.isOccupied)
            .help("Live-Abfrage starten oder pausieren (Leertaste). Die Verbindung bleibt bestehen.")
        }
    }

    private var emptyState: some View {
        VStack(spacing: Spacing.l) {
            EmptyState(symbol: "waveform.path.ecg", title: model.adapter == nil ? "Live-Daten brauchen eine Verbindung" : "Bereit für Live-Daten",
                       message: "Die App fragt nur die gewählten Werte ab, im Moment \(model.livePIDs.count). Der Motor darf laufen, die Zündung muss an sein.")
            Button("Live starten", systemImage: "play.fill") { Task { await model.toggleLive() } }
                .buttonStyle(.borderedProminent)
                .disabled(model.isOccupied)
        }
    }

    private var gauges: some View {
        let shown = Self.gaugePIDs.compactMap { pid in model.liveSeries.first { $0.pid == pid } }
        // One instrument strip with hairline dividers, like the timing strip in the cockpit. No tiles.
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 0)], spacing: 0) {
            ForEach(shown) { series in
                GaugeTile(series: series, dimmed: model.phase != .live, selected: series.id == selectedSeries?.id)
                    .overlay(alignment: .trailing) { Rectangle().fill(Palette.hairline).frame(width: 1).padding(.vertical, Spacing.m) }
                    .onTapGesture { model.selectedSeriesID = series.id }
                    .onTapGesture(count: 2) { if let latest = series.latest { model.inspect(.measurement(latest)) } }
            }
        }
        .overlay(alignment: .top) { Rectangle().fill(Palette.hairline).frame(height: 1) }
    }
}

struct GaugeTile: View {
    let series: LiveSeries
    let dimmed: Bool
    let selected: Bool

    var body: some View {
        let range = series.range
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack {
                Text(series.name).font(.obdLabel).foregroundStyle(Palette.textSecondary).lineLimit(1)
                Spacer()
                ConfidenceBadge(confidence: series.latest?.definition.confidence ?? .unknown, compact: true)
            }
            ArcGauge(fraction: series.latestValue.flatMap { value in range.map { $0.fraction(value) } },
                     valueText: series.format(series.latestValue), unit: series.unit,
                     lowerText: range.map { MeasuredValue.format($0.lower, decimals: 0) } ?? "",
                     upperText: range.map { MeasuredValue.format($0.upper, decimals: 0) } ?? "",
                     dimmed: dimmed)
                .frame(height: 140)
            HStack {
                Text("Min \(series.format(series.minimum))")
                Spacer()
                Text("Max \(series.format(series.maximum))")
            }
            .font(.obdCaption.monospacedDigit())
            .foregroundStyle(Palette.textTertiary)
        }
        .padding(Spacing.m)
        .overlay(alignment: .top) {
            if selected { Rectangle().fill(Color.accentColor).frame(height: 2) }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(series.name), \(series.format(series.latestValue)) \(series.unit)")
    }
}

/// Rows with confidence, name, sparkline and right aligned numbers.
struct ValueTable: View {
    let series: [LiveSeries]
    let selectedID: String?
    let dimmed: Bool
    let onSelect: (LiveSeries) -> Void
    let onInspect: (LiveSeries) -> Void
    @State private var width: CGFloat = 900

    /// Sparkline and statistics columns give way first when the table gets narrow.
    private var wide: Bool { width >= 720 }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ForEach(series) { item in
                row(item)
                    .background(item.id == selectedID ? Palette.live.opacity(0.08) : Color.clear)
                    .contentShape(Rectangle())
                    .onTapGesture { onSelect(item) }
                    .onTapGesture(count: 2) { onInspect(item) }
                    .contextMenu {
                        Button("Technik anzeigen") { onInspect(item) }
                        Button("Wert kopieren") { copyToPasteboard("\(item.name): \(item.format(item.latestValue)) \(item.unit)") }
                    }
                Divider()
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }

    /// The sparkline spans exactly the collected history, at most one minute, so it fills its column.
    private func sparkWindow(_ item: LiveSeries) -> TimeInterval {
        guard let first = item.points.first?.time, let last = item.points.last?.time else { return 60 }
        return min(60, max(1, last.timeIntervalSince(first)))
    }

    private var header: some View {
        HStack(spacing: Spacing.m) {
            Color.clear.frame(width: 16)
            Text("Messwert").frame(maxWidth: .infinity, alignment: .leading)
            if wide { Text("Verlauf").frame(width: 120, alignment: .leading) }
            Text("Wert").frame(width: 96, alignment: .trailing)
            if wide {
                Text("Min").frame(width: 72, alignment: .trailing)
                Text("Max").frame(width: 72, alignment: .trailing)
                Text("Mittel").frame(width: 72, alignment: .trailing)
            }
            Text("Einheit").frame(width: 56, alignment: .leading)
        }
        .font(.obdCaption)
        .foregroundStyle(Palette.textTertiary)
        .padding(.vertical, 6)
    }

    private func row(_ item: LiveSeries) -> some View {
        HStack(spacing: Spacing.m) {
            ConfidenceBadge(confidence: item.latest?.definition.confidence ?? .unknown, compact: true)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 0) {
                Text(item.name).font(.obdBody).foregroundStyle(Palette.textPrimary).lineLimit(1)
                Text("PID \(Hex.byteString(item.pid)) · \(item.ecu)").font(.obdCaption).foregroundStyle(Palette.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if wide {
                Group {
                    if item.points.count > 1 {
                        Sparkline(series: item, window: sparkWindow(item))
                    } else {
                        Color.clear
                    }
                }
                .frame(width: 120, height: 24)
            }
            numberCell(item.latest == nil ? nil : item.latestValue, item, width: 96, strong: true)
            if wide {
                numberCell(item.minimum, item, width: 72)
                numberCell(item.maximum, item, width: 72)
                numberCell(item.mean, item, width: 72)
            }
            Text(item.unit).font(.obdCaption).foregroundStyle(Palette.textSecondary).frame(width: 56, alignment: .leading)
        }
        .frame(minHeight: 36)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.name), \(item.format(item.latestValue)) \(item.unit)")
    }

    @ViewBuilder
    private func numberCell(_ value: Double?, _ item: LiveSeries, width: CGFloat, strong: Bool = false) -> some View {
        if let value {
            Text(item.format(value))
                .font(strong ? .obdMonoStrong : .obdMono)
                .foregroundStyle(dimmed ? Palette.textSecondary : (strong ? Palette.textPrimary : Palette.textSecondary))
                .frame(width: width, alignment: .trailing)
        } else if let latest = item.latest {
            Text(latest.displayNumber)
                .font(.obdCaption)
                .foregroundStyle(Palette.textSecondary)
                .lineLimit(1)
                .frame(width: width, alignment: .trailing)
        } else {
            StateLabel(state: .noResponse, font: .obdCaption).frame(width: width, alignment: .trailing)
        }
    }
}

/// Choice of polled values. Only values the vehicle reports as supported are offered when a report exists.
struct PIDPicker: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""

    var body: some View {
        let supported = supportedPIDs
        let definitions = J1979.allDefinitions.filter { definition in
            !J1979.isSupportQuery(definition.pid) && (supported?.contains(definition.pid) ?? true)
                && (query.isEmpty || definition.name.localizedCaseInsensitiveContains(query) || Hex.byteString(definition.pid).contains(query.uppercased()))
        }
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text("Werte für Live-Daten").font(.obdTitle)
            Text(supported == nil ? "Noch kein Bericht. Es werden alle genormten Werte angeboten, das Fahrzeug unterstützt eventuell nicht alle."
                 : "Angeboten werden nur Werte, die das Fahrzeug meldet. Weniger Werte ergeben schnellere Aktualisierung.")
                .font(.obdCaption)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            TextField("Suchen", text: $query).textFieldStyle(.roundedBorder)
            List {
                ForEach(PIDCategory.allCases, id: \.self) { category in
                    let items = definitions.filter { $0.category == category }
                    if !items.isEmpty {
                        Section(category.german) {
                            ForEach(items) { definition in
                                Toggle(isOn: binding(for: definition.pid)) {
                                    HStack {
                                        Text(definition.name)
                                        Spacer()
                                        Text(Hex.byteString(definition.pid)).font(.obdMono).foregroundStyle(Palette.textTertiary)
                                    }
                                }
                                .toggleStyle(.checkbox)
                            }
                        }
                    }
                }
            }
            .listStyle(.inset)
            HStack {
                Text("\(model.livePIDs.count) gewählt").font(.obdCaption).foregroundStyle(Palette.textSecondary)
                Spacer()
                Button("Standard") { Task { await model.setLivePIDs([0x0C, 0x0D, 0x05, 0x04, 0x42, 0x0B]) } }
            }
        }
        .padding(Spacing.l)
    }

    private var supportedPIDs: Set<UInt8>? {
        guard let ecus = model.report?.obd.ecus, !ecus.isEmpty else { return nil }
        let all = ecus.flatMap(\.supportedPIDs).compactMap { UInt8($0, radix: 16) }
        return all.isEmpty ? nil : Set(all)
    }

    private func binding(for pid: UInt8) -> Binding<Bool> {
        Binding {
            model.livePIDs.contains(pid)
        } set: { isOn in
            var pids = model.livePIDs
            if isOn, !pids.contains(pid) { pids.append(pid) }
            if !isOn { pids.removeAll { $0 == pid } }
            Task { await model.setLivePIDs(pids) }
        }
    }
}
