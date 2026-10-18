import Foundation
import Synchronization
import Testing
import OBDCore
@testable import AdapterKit

final class RecordingLink: AdapterLink {
    let label = "recording"
    let sent = Mutex<[String]>([])

    func transact(_ command: String, timeout: Duration) async throws -> LinkReply {
        sent.withLock { $0.append(command) }
        return LinkReply(text: "OK\r", elapsed: .zero)
    }

    func close() async {}
}

@Suite struct CommandPolicyTests {
    @Test(arguments: [
        "ATZ", "ATWS", "ATE0", "ATL0", "ATS1", "ATH1", "ATCAF1", "ATAT1", "ATI", "AT@1", "ATRV", "ATDP", "ATDPN",
        "ATCRA", "ATCRA7E8", "ATCRA 72E", "ATSH7E0", "ATSH 7DF", "ATSH18DAF110", "ATCF700", "ATCM700", "ATST32",
        "ATSP6", "ATSP0", "ATD0", "STI", "STIX", "STDI", "STMFR", "STSN", "STPR", "STPRS", "STPBRR",
        "STP33", "STP 53", "STPTO100", "STFAC", "STFPC", "STFPA 7E8,7FF", "STCFCPC", "STCFCPA 7E0,7E8",
        "STPX h:7E0, d:22F190, t:500, r:1", "STPX h:7DF, d:0100, t:300", "stpx d:0100",
        "0100", "01 0C", "22F190", "1902FF", "3E00", "0902",
    ])
    func allowedCommandsPass(_ command: String) throws {
        try CommandPolicy.validate(command)
    }

    @Test(arguments: [
        "", " ", "ATPP 0E SV 5A", "ATPPS", "STSDI Evil", "STSATI x", "STSBR 2000000", "STBR 2000000", "ATBRD 23",
        "STGPC34", "STMA", "ATMA", "STP99", "STP", "STPTO0", "STPTO70000", "ATSHXYZ", "ATCRA7E", "ATSP D",
        "STPX h:7E0, d:2EF19000", "STPX h:7E0, d:2701", "STPX h:7E0, l:3", "STPX h:7E0, d:22F190, f:1",
        "STPX h:7E0", "STPX h:7E00, d:0100", "STPX d:0100, d:0100", "STPX h:7E0, d:22F190, t:abc",
        "2EF19000", "1002", "1003", "04", "14FFFFFF", "3101FF00", "ABC", "XYZ",
    ])
    func everythingElseIsDenied(_ command: String) {
        #expect(throws: OBDError.self) { try CommandPolicy.validate(command) }
    }

    @Test func safeLinkBlocksBeforeTheWire() async throws {
        let recording = RecordingLink()
        let link = SafeLink(recording)
        _ = try await link.transact("ATI", timeout: .seconds(1))
        await #expect(throws: OBDError.self) { _ = try await link.transact("2E F1 90 00", timeout: .seconds(1)) }
        await #expect(throws: OBDError.self) { _ = try await link.transact("ATPP 0E SV 00", timeout: .seconds(1)) }
        #expect(recording.sent.withLock { $0 } == ["ATI"])
        #expect(link.label == "recording")
    }
}
