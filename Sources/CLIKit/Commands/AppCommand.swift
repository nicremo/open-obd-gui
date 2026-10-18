import ArgumentParser
import DiagnosticEngine

struct AppStatus: Encodable, Sendable {
    let reachable: Bool
    let socket: String
    let hello: BridgeHello?
    /// What `--route auto` would do right now.
    let autoRoute: String
}

struct AppCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "app",
        abstract: "Zeigt, ob Open OBD GUI läuft und Agenten über --via-app bedient.")

    @OptionGroup var output: OutputOptions

    @Option(help: ArgumentHelp("Socket der App-Brücke (für Tests).", visibility: .private))
    var bridgeSocket: String?

    func run() async throws {
        try await CLI.execute("app", json: output.json) { _ in await Self.perform(socket: bridgeSocket ?? BridgeEndpoint.defaultPath) }
    }

    static func perform(socket: String) async -> CLIResult<AppStatus> {
        var hello: BridgeHello?
        if BridgeClient.isReachable(at: socket), let client = try? await BridgeClient.connect(at: socket) {
            hello = client.hello
            await client.close()
        }
        let auto = hello.map { $0.simulated ? "direct" : "app" } ?? "direct"
        let status = AppStatus(reachable: hello != nil, socket: socket, hello: hello, autoRoute: auto)
        let human: String
        if let hello {
            let state = hello.activity.map { ", gerade: \($0)" } ?? ""
            human = "\(hello.app) läuft und nimmt Aufträge an.\nVerbindung der App: \(hello.link)\(hello.simulated ? " (Simulator)" : "")\(state)\n--route auto geht \(auto == "app" ? "über die App" : "direkt")."
        } else {
            human = "Open OBD GUI läuft nicht oder bietet keinen Agent-Zugang an (\(socket))."
        }
        return CLIResult(data: status, human: human)
    }
}
