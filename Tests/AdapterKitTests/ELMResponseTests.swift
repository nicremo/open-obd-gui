import Testing
import OBDCore
@testable import AdapterKit

@Suite struct ELMResponseTests {
    @Test func parsesSingleAndMultipleECUFrames() {
        let response = ELMResponseParser.parse("7E8 06 41 00 BE 3F A8 13\r7E9 06 41 00 98 18 80 11\r\r", command: "0100")
        #expect(response.frames == [
            CANFrame(id: CANIdentifier(0x7E8), data: [0x06, 0x41, 0x00, 0xBE, 0x3F, 0xA8, 0x13]),
            CANFrame(id: CANIdentifier(0x7E9), data: [0x06, 0x41, 0x00, 0x98, 0x18, 0x80, 0x11]),
        ])
        #expect(response.errors.isEmpty)
        #expect(!response.isOK)
    }

    @Test func removesEchoAndHandlesLinefeeds() {
        let response = ELMResponseParser.parse("ATE0\r\nOK\r\n\r\n", command: "ATE0")
        #expect(response.lines == [.ok])
        #expect(response.isOK)
    }

    @Test func echoMatchIgnoresSpacesAndCase() {
        let response = ELMResponseParser.parse("stpx h:7e0, d:0100\r7E8 06 41 00 BE 3F A8 13\r", command: "STPX h:7E0, d:0100")
        #expect(response.frames.count == 1)
    }

    @Test func classifiesStatusLines() {
        #expect(ELMResponseParser.parse("?\r", command: "STI").isUnknownCommand)
        #expect(ELMResponseParser.parse("NO DATA\r", command: "22F190").isNoData)
        #expect(ELMResponseParser.parse("SEARCHING...\rNO DATA\r", command: "0100").lines == [.searching, .noData])
        #expect(ELMResponseParser.parse("ELM327 v1.4b\r", command: "ATI").texts == ["ELM327 v1.4b"])
        #expect(ELMResponseParser.parse("12.6V\r", command: "ATRV").texts == ["12.6V"])
    }

    @Test(arguments: ELMErrorKind.allCases)
    func classifiesEveryErrorKind(_ kind: ELMErrorKind) {
        #expect(ELMResponseParser.parse("\(kind.rawValue)\r", command: "0100").errors == [kind])
    }

    @Test func keepsFramesNextToErrors() {
        let response = ELMResponseParser.parse("7E8 03 41 0D 32\rBUFFER FULL\r", command: "010D")
        #expect(response.frames.count == 1)
        #expect(response.errors == [.bufferFull])
    }

    @Test func parsesExtendedIdentifiersOnlyWhenRequested() {
        let line = "18 DA F1 10 03 7E 00 00\r"
        #expect(ELMResponseParser.parse(line, command: "3E00").frames.isEmpty)
        let response = ELMResponseParser.parse(line, command: "3E00", extendedIDs: true)
        #expect(response.frames == [CANFrame(id: CANIdentifier(0x18DAF110, extended: true), data: [0x03, 0x7E, 0x00, 0x00])])
    }

    @Test func textThatLooksAlmostLikeAFrameIsText() {
        #expect(ELMResponseParser.parse("ABC\r", command: "ATI").texts == ["ABC"])
        #expect(ELMResponseParser.parse("7E8 4\r", command: "0100").texts == ["7E8 4"])
        #expect(ELMResponseParser.parse("STN2232 v5.10.3\r", command: "STI").texts == ["STN2232 v5.10.3"])
    }

    @Test func summaryIsReadable() {
        #expect(ELMResponseParser.parse("CAN ERROR\r", command: "0100").summary == "CAN ERROR")
        #expect(ELMResponseParser.parse("", command: "0100").summary == "(keine Antwort)")
    }
}
