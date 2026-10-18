import Testing
@testable import DiagnosticEngine

@Suite struct OpenOBDTests {
    @Test func identityIsStable() {
        #expect(OpenOBD.toolName == "openobd")
        #expect(OpenOBD.toolDescription == "openobd \(OpenOBD.version)")
    }
}
