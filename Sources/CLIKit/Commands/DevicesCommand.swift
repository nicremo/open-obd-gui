import AdapterKit
import ArgumentParser

struct DevicesCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "devices",
        abstract: "Zeigt serielle Geräte und wie wahrscheinlich sie ein OBD-Adapter sind.")

    @OptionGroup var output: OutputOptions

    func run() async throws {
        try await CLI.execute("devices", json: output.json) { _ in Self.perform() }
    }

    static func perform() -> CLIResult<[SerialDeviceCandidate]> {
        let devices = DeviceDiscovery.candidates()
        return CLIResult(data: devices, human: HumanFormat.devices(devices))
    }
}
