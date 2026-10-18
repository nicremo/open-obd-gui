import Foundation

/// Product identity used in reports, captures and the CLI.
public enum OpenOBD {
    public static let toolName = "openobd"
    public static let version = "0.1.0"
    public static var toolDescription: String { "\(toolName) \(version)" }
}
