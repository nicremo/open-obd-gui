import AdapterKit
import ArgumentParser
import DiagnosticEngine
import Foundation
import OBDCore
import VehicleSim

struct OutputOptions: ParsableArguments {
    @Flag(help: "Ein JSON-Objekt nach Schema openobd.cli/1 ausgeben (für Agenten).")
    var json = false
}

struct ConnectionOptions: ParsableArguments {
    @Option(help: "Serieller Port des Adapters, zum Beispiel /dev/cu.usbserial-A1B2. Ohne Angabe wird der beste Kandidat gewählt.")
    var port: String?

    @Option(help: "Simulator statt Adapter: mondeo-mk4 oder focus-mk4.")
    var sim: String?

    @Option(help: "Mitschnitt (JSON Lines) abspielen statt Adapter.")
    var replay: String?

    @Option(help: "Abspielmodus für --replay: strict oder lookup.")
    var replayMode = "lookup"

    @Option(help: "Gesamten Adapterverkehr als JSON Lines in diese Datei schreiben.")
    var capture: String?

    @Option(help: "Fahrzeugprofil als Hinweis: mondeo-mk4 oder focus-mk4.")
    var vehicle: String?

    @Flag(help: "Adapterverkehr auf stderr ausgeben.")
    var verbose = false

    @Flag(help: "In der laufenden App Open OBD GUI ausführen. Die App zeigt Fortschritt und Verkehr.")
    var viaApp = false

    @Option(help: "Weg zum Fahrzeug: direct (Standard), app oder auto. auto nutzt die App, wenn sie mit einem echten Adapter verbunden ist.")
    var route: String?

    @Option(help: ArgumentHelp("Socket der App-Brücke (für Tests).", visibility: .private))
    var bridgeSocket: String?

    func spec() throws -> ConnectionSpec {
        var spec = ConnectionSpec(port: port, sim: sim, replay: replay, replayMode: replayMode, capture: capture, vehicle: vehicle,
                                  verbose: verbose, bridgeSocket: bridgeSocket)
        if let route {
            spec.route = try ConnectionSpec.route(route)
        }
        if viaApp {
            guard route == nil || spec.route == .app else {
                throw CLIError.usage("--via-app und --route \(route ?? "") widersprechen sich.")
            }
            spec.route = .app
        }
        return spec
    }

    func connector(_ context: CLIContext, progress: Bool = false) -> Connector {
        { try await spec().open(context, progress: progress) }
    }
}

enum ArgumentParsing {
    static func module(_ text: String) throws -> UInt32 {
        guard text.count == 3, let value = Hex.parseCANID(text.uppercased()), (0x700...0x7FF).contains(value) else {
            throw CLIError.usage("\(text) ist keine Moduladresse. Erwartet drei Hex-Ziffern von 700 bis 7FF, zum Beispiel 7E0.")
        }
        return value
    }

    static func bus(_ text: String) throws -> BusKind {
        switch text.lowercased() {
        case "hs", "hs-can", "hscan": return .hsCAN
        case "ms", "ms-can", "mscan": return .msCAN
        default: throw CLIError.usage("Unbekannter Bus \(text). Erlaubt: hs, ms")
        }
    }

    static func did(_ text: String) throws -> UInt16 {
        guard text.count == 4, Hex.isHexDigits(text), let value = UInt16(text, radix: 16) else {
            throw CLIError.usage("\(text) ist keine DID. Erwartet vier Hex-Ziffern, zum Beispiel F190.")
        }
        return value
    }

    static func pid(_ text: String) throws -> UInt8 {
        guard text.count == 2, Hex.isHexDigits(text), let value = UInt8(text, radix: 16) else {
            throw CLIError.usage("\(text) ist keine PID. Erwartet zwei Hex-Ziffern, zum Beispiel 0C.")
        }
        return value
    }

    static func payload(_ parts: [String]) throws -> [UInt8] {
        let text = parts.joined(separator: " ")
        guard let bytes = try? Hex.decode(text), !bytes.isEmpty else {
            throw CLIError.usage("\(text) sind keine Hex-Nutzdaten. Beispiel: \"22 F1 90\"")
        }
        return bytes
    }
}
