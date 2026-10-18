import DiagnosticEngine
import FordKnowledge
import OBDCore
import OpenOBDAppCore
import SwiftUI

/// One control module on the track map.
struct MapMarker: Identifiable, Equatable {
    let id: String
    let label: String
    let name: String
    let zone: VehicleZone
    let bus: BusKind?
    let severity: Severity?
    let faultCount: Int
    /// Found during a running scan, not evaluated yet.
    var pending = false

    var flag: Flag { pending ? .info : Flag(severity) }

    var status: String {
        if pending { return "gefunden" }
        return faultCount == 0 ? "frei" : (faultCount == 1 ? "1 Fehler" : "\(faultCount) Fehler")
    }

    static func from(report: VehicleReport) -> [MapMarker] {
        report.modules.map { module in
            let faults = FaultGroup.groups(from: report.faults(of: module.requestID))
            return MapMarker(id: module.id, label: module.acronym ?? module.requestID, name: module.name,
                             zone: module.zone ?? .cabinCenter, bus: module.bus,
                             severity: faults.map(\.severity).max(), faultCount: faults.count)
        }
    }

    static func from(found: [DiscoveredModule]) -> [MapMarker] {
        found.map { module in
            let definition = KnowledgeBase.bundled.module(request: module.requestID)
            return MapMarker(id: module.id, label: module.catalogAcronym ?? module.requestHex,
                             name: definition?.nameDE ?? "Steuergerät \(module.requestHex)",
                             zone: definition?.zone ?? .cabinCenter, bus: module.bus,
                             severity: nil, faultCount: 0, pending: true)
        }
    }
}

/// Positions of nodes, tags and the OBD socket for one size. Pure geometry, no views.
struct TrackGeometry {
    struct Placement: Identifiable {
        let marker: MapMarker
        let node: CGPoint
        let tag: CGRect
        var id: String { marker.id }
        var displaced: Bool { abs(tag.midY - node.y) > 4 }
    }

    static let carRatio: CGFloat = 0.44
    static let tagWidth: CGFloat = 132
    static let compactTagWidth: CGFloat = 86
    static let tagHeight: CGFloat = 26
    static let gap: CGFloat = 30
    let car: CGRect
    let socket: CGPoint
    let placements: [Placement]
    /// Tags stand in columns beside the car and point to their node with a leader line.
    let columns: Bool
    /// Tags show flag, code and fault count only.
    let compact: Bool

    init(size: CGSize, markers: [MapMarker], showTags: Bool) {
        // Callout columns on both sides; with little room the tags shrink to flag, code and count.
        // Only very narrow maps fall back to tags beside their nodes.
        var tagWidth = Self.tagWidth
        var height = min(size.height - 24, (size.width - (showTags ? 2 * (tagWidth + Self.gap + 6) : 24)) / Self.carRatio)
        var mode = showTags ? Layout.both : Layout.none
        if showTags && height * Self.carRatio < 190 {
            tagWidth = Self.compactTagWidth
            height = min(size.height - 24, (size.width - 2 * (tagWidth + Self.gap + 6)) / Self.carRatio)
            if height * Self.carRatio < 150 {
                mode = .inline
                height = min(size.height - 24, (size.width - 200) / Self.carRatio)
            }
        }
        columns = mode == .both
        compact = tagWidth == Self.compactTagWidth
        let width = height * Self.carRatio
        car = CGRect(x: (size.width - width) / 2, y: (size.height - height) / 2, width: width, height: height)

        var nodes: [(MapMarker, CGPoint)] = []
        let groups = Dictionary(grouping: markers, by: \.zone)
        for zone in VehicleZone.allCases {
            let group = (groups[zone] ?? []).sorted { $0.label < $1.label }
            let anchor = Self.anchor(zone)
            let vertical = zone == .doorsLeft || zone == .doorsRight
            for (index, marker) in group.enumerated() {
                let shift = (CGFloat(index) - CGFloat(group.count - 1) / 2) * (vertical ? 0.08 : 0.2)
                let x = vertical ? anchor.x : min(0.86, max(0.14, anchor.x + shift))
                // Modules of one zone sit on staggered rows, so their leader lines never share a segment.
                let stagger = vertical ? 0 : (CGFloat(index) - CGFloat(group.count - 1) / 2) * 0.045
                let y = vertical ? anchor.y + shift : anchor.y + stagger
                nodes.append((marker, CGPoint(x: car.minX + car.width * x, y: car.minY + car.height * y)))
            }
        }

        // The OBD socket sits in the driver's footwell, on the first spot that keeps clear of every node,
        // so the origin of all bus lines is never hidden.
        let carRect = car
        let spots: [CGPoint] = [(0.30, 0.385), (0.24, 0.40), (0.36, 0.37), (0.22, 0.48), (0.40, 0.41), (0.28, 0.33)]
            .map { CGPoint(x: carRect.minX + carRect.width * $0.0, y: carRect.minY + carRect.height * $0.1) }
        socket = spots.first { spot in nodes.allSatisfy { hypot($0.1.x - spot.x, $0.1.y - spot.y) >= 30 } } ?? spots[0]

        guard showTags else {
            placements = nodes.map { Placement(marker: $0.0, node: $0.1, tag: .zero) }
            return
        }
        switch mode {
        case .both: placements = Self.columnPlacements(nodes, car: car, size: size, tagWidth: tagWidth)
        default: placements = Self.inlinePlacements(nodes, car: car, size: size)
        }
    }

    enum Layout { case both, inline, none }

    /// Left and right callout columns, each sorted by the height of its nodes and spread without overlap.
    static func columnPlacements(_ nodes: [(MapMarker, CGPoint)], car: CGRect, size: CGSize, tagWidth: CGFloat) -> [Placement] {
        var left: [(MapMarker, CGPoint)] = []
        var right: [(MapMarker, CGPoint)] = []
        for entry in nodes.sorted(by: { $0.1.y < $1.1.y }) {
            if entry.1.x < car.midX - 1 { left.append(entry) }
            else if entry.1.x > car.midX + 1 { right.append(entry) }
            else if left.count < right.count { left.append(entry) }
            else { right.append(entry) }
        }
        func spread(_ side: [(MapMarker, CGPoint)], x: CGFloat) -> [Placement] {
            var tops = side.map { $0.1.y - tagHeight / 2 }
            for index in tops.indices.dropFirst() {
                tops[index] = max(tops[index], tops[index - 1] + tagHeight + 6)
            }
            if let last = tops.last, last + tagHeight > size.height - 4 {
                let shift = last + tagHeight - (size.height - 4)
                tops = tops.map { $0 - shift }
                for index in tops.indices.reversed().dropFirst() {
                    tops[index] = min(tops[index], tops[index + 1] - tagHeight - 6)
                }
            }
            return zip(side, tops).map { entry, top in
                Placement(marker: entry.0, node: entry.1, tag: CGRect(x: x, y: max(4, top), width: tagWidth, height: tagHeight))
            }
        }
        return spread(left, x: car.minX - gap - tagWidth) + spread(right, x: car.maxX + gap)
    }

    /// Fallback for narrow maps: tags beside their node, giving way downwards on collision.
    static func inlinePlacements(_ nodes: [(MapMarker, CGPoint)], car: CGRect, size: CGSize) -> [Placement] {
        var placed: [Placement] = []
        for (marker, node) in nodes.sorted(by: { $0.1.y < $1.1.y }) {
            let width = CGFloat(56 + marker.label.count * 8 + marker.status.count * 6)
            let toRight = node.x <= car.midX + 1
            var rect = CGRect(x: toRight ? node.x + 12 : node.x - 12 - width, y: node.y - tagHeight / 2, width: width, height: tagHeight)
            var guardCount = 0
            while let blocker = placed.first(where: { $0.tag.insetBy(dx: -3, dy: -3).intersects(rect) }), guardCount < 30 {
                rect.origin.y = blocker.tag.maxY + 5
                guardCount += 1
            }
            rect.origin.x = min(max(4, rect.origin.x), size.width - rect.width - 4)
            rect.origin.y = min(max(4, rect.origin.y), size.height - rect.height - 4)
            placed.append(Placement(marker: marker, node: node, tag: rect))
        }
        return placed
    }

    /// Typical installation place, front at the top, driver on the left.
    static func anchor(_ zone: VehicleZone) -> CGPoint {
        switch zone {
        case .front: CGPoint(x: 0.5, y: 0.07)
        case .engineBay: CGPoint(x: 0.5, y: 0.18)
        case .roof: CGPoint(x: 0.5, y: 0.335)
        case .cabinFront: CGPoint(x: 0.5, y: 0.45)
        case .cabinCenter: CGPoint(x: 0.5, y: 0.57)
        case .cabinRear: CGPoint(x: 0.5, y: 0.69)
        case .doorsLeft: CGPoint(x: 0.08, y: 0.55)
        case .doorsRight: CGPoint(x: 0.92, y: 0.55)
        case .rear: CGPoint(x: 0.5, y: 0.92)
        }
    }
}

/// Signature of the timing world: the car as the track, control modules as the field.
/// Nodes sit at the typical installation place, the CAN buses run from the OBD socket.
struct TrackMap: View {
    let markers: [MapMarker]
    var selection: String?
    var showTags = true
    var onSelect: ((MapMarker) -> Void)?
    @State private var hovered: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let geometry = TrackGeometry(size: proxy.size, markers: markers, showTags: showTags)
            ZStack(alignment: .topLeading) {
                CarDrawing()
                    .frame(width: geometry.car.width, height: geometry.car.height)
                    .offset(x: geometry.car.minX, y: geometry.car.minY)
                Canvas { context, _ in
                    drawBuses(context, geometry)
                    drawLeaders(context, geometry)
                    drawNodes(context, geometry)
                    drawSocket(context, geometry)
                }
                .allowsHitTesting(false)
                if showTags {
                    ForEach(geometry.placements) { placement in
                        TrackTag(marker: placement.marker, selected: placement.marker.id == selection || placement.marker.id == hovered,
                                 compact: geometry.compact)
                            .frame(width: placement.tag.width, height: placement.tag.height)
                            .offset(x: placement.tag.minX, y: placement.tag.minY)
                            .onHover { hovered = $0 ? placement.marker.id : (hovered == placement.marker.id ? nil : hovered) }
                            .onTapGesture { onSelect?(placement.marker) }
                            .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    }
                } else if let selected = geometry.placements.first(where: { $0.marker.id == selection }) {
                    Text(selected.marker.label)
                        .font(.timing(12, .heavy))
                        .foregroundStyle(Palette.textPrimary)
                        .padding(.horizontal, 5)
                        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.tag))
                        .overlay(RoundedRectangle(cornerRadius: Radius.tag).strokeBorder(Palette.textPrimary, lineWidth: 1))
                        .fixedSize()
                        .offset(x: selected.node.x + 10, y: selected.node.y - 9)
                }
                Text("OBD")
                    .font(.timing(10, .heavy))
                    .foregroundStyle(Palette.textSecondary)
                    .offset(x: geometry.socket.x - 9, y: geometry.socket.y + 8)
                    .accessibilityHidden(true)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: markers)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Streckenkarte mit \(markers.count) Steuergeräten")
    }

    private func drawBuses(_ context: GraphicsContext, _ geometry: TrackGeometry) {
        for bus in BusKind.allCases {
            let nodes = geometry.placements.filter { $0.marker.bus == bus }.map(\.node).sorted { $0.y < $1.y }
            guard !nodes.isEmpty else { continue }
            var path = Path()
            path.move(to: geometry.socket)
            var previous = geometry.socket
            for node in nodes {
                let mid = CGPoint(x: (previous.x + node.x) / 2, y: (previous.y + node.y) / 2)
                path.addQuadCurve(to: mid, control: CGPoint(x: previous.x, y: mid.y))
                path.addQuadCurve(to: node, control: CGPoint(x: node.x, y: mid.y))
                previous = node
            }
            let style = bus == .hsCAN
                ? StrokeStyle(lineWidth: showTags ? 2.5 : 1.5, lineCap: .round, lineJoin: .round)
                : StrokeStyle(lineWidth: showTags ? 2 : 1.25, lineCap: .round, lineJoin: .round, dash: [6, 5])
            context.stroke(path, with: .color((bus == .hsCAN ? Palette.hsCAN : Palette.msCAN).opacity(showTags ? 0.85 : 0.5)), style: style)
        }
    }

    private func drawLeaders(_ context: GraphicsContext, _ geometry: TrackGeometry) {
        guard showTags else { return }
        for placement in geometry.placements where geometry.columns || placement.displaced {
            let selected = placement.marker.id == selection || placement.marker.id == hovered
            var path = Path()
            path.move(to: placement.node)
            let toRight = placement.tag.midX > placement.node.x
            let tagEdge = toRight ? placement.tag.minX : placement.tag.maxX
            if geometry.columns {
                let elbow = toRight ? geometry.car.maxX + 8 : geometry.car.minX - 8
                path.addLine(to: CGPoint(x: elbow, y: placement.node.y))
                path.addLine(to: CGPoint(x: tagEdge - (toRight ? 6 : -6), y: placement.tag.midY))
            }
            path.addLine(to: CGPoint(x: tagEdge, y: placement.tag.midY))
            context.stroke(path, with: .color(selected ? Palette.textPrimary : Palette.hairlineStrong),
                           style: StrokeStyle(lineWidth: selected ? 1.5 : 1, lineCap: .round, lineJoin: .round))
        }
    }

    private func drawNodes(_ context: GraphicsContext, _ geometry: TrackGeometry) {
        for placement in geometry.placements {
            let selected = placement.marker.id == selection || placement.marker.id == hovered
            let radius: CGFloat = showTags ? 6 : 4.5
            let node = placement.node
            if selected {
                let ring = Path(ellipseIn: CGRect(x: node.x - radius - 5, y: node.y - radius - 5, width: (radius + 5) * 2, height: (radius + 5) * 2))
                context.stroke(ring, with: .color(Palette.textPrimary), lineWidth: 1.5)
            }
            let dot = Path(ellipseIn: CGRect(x: node.x - radius, y: node.y - radius, width: radius * 2, height: radius * 2))
            context.fill(dot, with: .color(Self.cloth(placement.marker.flag)))
            context.stroke(dot, with: .color(Palette.background), lineWidth: 2)
            if placement.marker.flag == .defect {
                let disc = Path(ellipseIn: CGRect(x: node.x - radius * 0.45, y: node.y - radius * 0.45, width: radius * 0.9, height: radius * 0.9))
                context.fill(disc, with: .color(FlagCloth.orange))
            }
        }
    }

    /// The OBD socket as its real D shape: wider on top, two rows of pins.
    private func drawSocket(_ context: GraphicsContext, _ geometry: TrackGeometry) {
        let c = geometry.socket
        let scale: CGFloat = showTags ? 1 : 0.75
        var body = Path()
        body.move(to: CGPoint(x: c.x - 10 * scale, y: c.y - 6 * scale))
        body.addLine(to: CGPoint(x: c.x + 10 * scale, y: c.y - 6 * scale))
        body.addLine(to: CGPoint(x: c.x + 7.5 * scale, y: c.y + 6 * scale))
        body.addLine(to: CGPoint(x: c.x - 7.5 * scale, y: c.y + 6 * scale))
        body.closeSubpath()
        context.fill(body, with: .color(Palette.textPrimary))
        for row in 0..<2 {
            let y = c.y + (row == 0 ? -2.2 : 2.2) * scale
            let count = row == 0 ? 5 : 4
            for index in 0..<count {
                let x = c.x + (CGFloat(index) - CGFloat(count - 1) / 2) * 3.4 * scale
                context.fill(Path(ellipseIn: CGRect(x: x - 0.9 * scale, y: y - 0.9 * scale, width: 1.8 * scale, height: 1.8 * scale)),
                             with: .color(Palette.background))
            }
        }
    }

    static func cloth(_ flag: Flag) -> Color {
        switch flag {
        case .clear: FlagCloth.green
        case .info: FlagCloth.blue
        case .caution: FlagCloth.yellow
        case .defect: FlagCloth.black
        case .stop: FlagCloth.red
        }
    }
}

/// Timing tag of a module: flag, three-letter code, status.
struct TrackTag: View {
    let marker: MapMarker
    let selected: Bool
    var compact = false

    var body: some View {
        HStack(spacing: 6) {
            FlagGlyph(flag: marker.flag, width: 12)
            Text(marker.label)
                .font(.timing(14, .heavy))
                .foregroundStyle(Palette.textPrimary)
            if !compact {
                Text(marker.status)
                    .font(.system(size: 11))
                    .foregroundStyle(marker.faultCount > 0 ? Palette.textPrimary : Palette.textSecondary)
            } else if marker.faultCount > 0 {
                Text("\(marker.faultCount)")
                    .font(.timing(13, .bold))
                    .foregroundStyle(Palette.textPrimary)
            }
        }
        .lineLimit(1)
        .padding(.horizontal, 7)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(selected ? Palette.selection : Palette.surface, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
            .strokeBorder(selected ? Color.accentColor : Palette.hairline, lineWidth: 1))
        .contentShape(Rectangle())
        .help("\(marker.name): \(marker.status)")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(marker.label), \(marker.name), \(marker.status)")
        .accessibilityAddTraits(.isButton)
    }
}

/// Car seen from above, front at the top, drawn in the palette of the appearance:
/// a dark body on the timing monitor, white paper with ink lines in the printed sheet.
struct CarDrawing: View {
    var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * w, y: y * h) }
            func mirrored(_ points: [CGPoint]) -> [CGPoint] { points.map { CGPoint(x: w - $0.x, y: $0.y) } }

            // Tyres first, the body covers their inner half.
            for (x, y) in [(-0.035, 0.125), (0.875, 0.125), (-0.035, 0.735), (0.875, 0.735)] {
                let tyre = Path(roundedRect: CGRect(x: x * w, y: y * h, width: 0.16 * w, height: 0.14 * h), cornerRadius: 0.05 * w, style: .continuous)
                context.fill(tyre, with: .color(Palette.carTyre))
            }

            // Body outline, built for the right half and mirrored.
            var body = Path()
            body.move(to: p(0.5, 0))
            body.addCurve(to: p(0.9, 0.05), control1: p(0.74, 0), control2: p(0.86, 0.015))
            body.addCurve(to: p(0.985, 0.2), control1: p(0.96, 0.09), control2: p(0.98, 0.14))
            body.addCurve(to: p(0.955, 0.46), control1: p(0.995, 0.3), control2: p(0.96, 0.38))
            body.addLine(to: p(0.96, 0.74))
            body.addCurve(to: p(0.985, 0.86), control1: p(0.97, 0.79), control2: p(0.985, 0.82))
            body.addCurve(to: p(0.86, 0.985), control1: p(0.985, 0.94), control2: p(0.95, 0.975))
            body.addCurve(to: p(0.5, 1), control1: p(0.76, 0.998), control2: p(0.62, 1))
            body.addCurve(to: p(0.14, 0.985), control1: p(0.38, 1), control2: p(0.24, 0.998))
            body.addCurve(to: p(0.015, 0.86), control1: p(0.05, 0.975), control2: p(0.015, 0.94))
            body.addCurve(to: p(0.04, 0.74), control1: p(0.015, 0.82), control2: p(0.03, 0.79))
            body.addLine(to: p(0.045, 0.46))
            body.addCurve(to: p(0.015, 0.2), control1: p(0.04, 0.38), control2: p(0.005, 0.3))
            body.addCurve(to: p(0.1, 0.05), control1: p(0.02, 0.14), control2: p(0.04, 0.09))
            body.addCurve(to: p(0.5, 0), control1: p(0.14, 0.015), control2: p(0.26, 0))
            body.closeSubpath()
            context.fill(body, with: .color(Palette.carBody))
            context.stroke(body, with: .color(Palette.carBodyEdge), lineWidth: 1.5)

            // Mirrors.
            for points in [[p(0.04, 0.33), p(-0.06, 0.335), p(-0.06, 0.365), p(0.04, 0.37)]] {
                for shape in [points, mirrored(points)] {
                    var mirror = Path()
                    mirror.addLines(shape)
                    mirror.closeSubpath()
                    context.fill(mirror, with: .color(Palette.carBody))
                    context.stroke(mirror, with: .color(Palette.carBodyEdge), lineWidth: 1)
                }
            }

            // Hood creases.
            for points in [[p(0.3, 0.035), p(0.27, 0.16), p(0.25, 0.29)]] {
                for shape in [points, mirrored(points)] {
                    var crease = Path()
                    crease.move(to: shape[0])
                    crease.addQuadCurve(to: shape[2], control: shape[1])
                    context.stroke(crease, with: .color(Palette.carBodyEdge.opacity(0.6)), lineWidth: 1)
                }
            }

            // Windscreen, side windows, rear window.
            var screen = Path()
            screen.move(to: p(0.15, 0.31))
            screen.addQuadCurve(to: p(0.85, 0.31), control: p(0.5, 0.265))
            screen.addLine(to: p(0.77, 0.415))
            screen.addQuadCurve(to: p(0.23, 0.415), control: p(0.5, 0.395))
            screen.closeSubpath()
            context.fill(screen, with: .color(Palette.carGlass))
            context.stroke(screen, with: .color(Palette.carBodyEdge), lineWidth: 1)

            for points in [[p(0.12, 0.42), p(0.19, 0.43), p(0.19, 0.71), p(0.13, 0.72)]] {
                for shape in [points, mirrored(points)] {
                    var window = Path()
                    window.addLines(shape)
                    window.closeSubpath()
                    context.fill(window, with: .color(Palette.carGlass))
                }
            }

            var rear = Path()
            rear.move(to: p(0.22, 0.735))
            rear.addQuadCurve(to: p(0.78, 0.735), control: p(0.5, 0.75))
            rear.addLine(to: p(0.83, 0.82))
            rear.addQuadCurve(to: p(0.17, 0.82), control: p(0.5, 0.85))
            rear.closeSubpath()
            context.fill(rear, with: .color(Palette.carGlass))
            context.stroke(rear, with: .color(Palette.carBodyEdge), lineWidth: 1)

            // Roof panel.
            let roof = Path(roundedRect: CGRect(x: 0.21 * w, y: 0.425 * h, width: 0.58 * w, height: 0.3 * h), cornerRadius: 0.08 * w, style: .continuous)
            context.stroke(roof, with: .color(Palette.carBodyEdge.opacity(0.7)), lineWidth: 1)

            // Lamps.
            for points in [[p(0.13, 0.04), p(0.33, 0.018), p(0.34, 0.035), p(0.15, 0.065)]] {
                for shape in [points, mirrored(points)] {
                    var lamp = Path()
                    lamp.addLines(shape)
                    lamp.closeSubpath()
                    context.fill(lamp, with: .color(Palette.textSecondary.opacity(0.55)))
                }
            }
            for points in [[p(0.1, 0.955), p(0.3, 0.975), p(0.3, 0.99), p(0.12, 0.975)]] {
                for shape in [points, mirrored(points)] {
                    var lamp = Path()
                    lamp.addLines(shape)
                    lamp.closeSubpath()
                    context.fill(lamp, with: .color(FlagCloth.red.opacity(0.8)))
                }
            }
        }
        .accessibilityHidden(true)
    }
}
