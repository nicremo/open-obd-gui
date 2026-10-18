import Testing
@testable import OBDCore

@Suite struct FoundationTests {
    @Test func encodesUppercaseHexWithOptionalSeparator() {
        #expect(Hex.encode([0x01, 0xAB, 0xFF]) == "01ABFF")
        #expect(Hex.encode([0x7E, 0x00], separator: " ") == "7E 00")
        #expect(Hex.byteString(0x0F) == "0F")
    }

    @Test func decodesHexIgnoringWhitespaceAndCase() throws {
        #expect(try Hex.decode("22 f1 90") == [0x22, 0xF1, 0x90])
        #expect(try Hex.decode("") == [])
    }

    @Test func rejectsOddLengthAndInvalidDigits() {
        #expect(throws: OBDError.self) { try Hex.decode("ABC") }
        #expect(throws: OBDError.self) { try Hex.decode("ZZ") }
        #expect(throws: OBDError.self) { try Hex.decode("+1") }
    }

    @Test func formatsAndParsesCANIdentifiers() {
        #expect(Hex.canID(0x7E8, extended: false) == "7E8")
        #expect(Hex.canID(0x7, extended: false) == "007")
        #expect(Hex.canID(0x18DAF110, extended: true) == "18DAF110")
        #expect(Hex.parseCANID("7E8") == 0x7E8)
        #expect(Hex.parseCANID("18DAF110") == 0x18DAF110)
        #expect(Hex.parseCANID("7E") == nil)
        #expect(Hex.parseCANID("7G8") == nil)
    }

    @Test func errorCodesAndMessagesAreStable() {
        #expect(OBDError.policyDenied("x").code == "POLICY_DENIED")
        #expect(OBDError.adapterNotFound.hint != nil)
        #expect(OBDError.negativeResponse(service: 0x22, code: 0x31).message.contains("außerhalb des Bereichs"))
    }

    @Test func negativeResponseCodesHaveGermanText() {
        #expect(NegativeResponseCode.german(0x11) == "Dienst nicht unterstützt")
        #expect(NegativeResponseCode.name(0x78) == "requestCorrectlyReceivedResponsePending")
        #expect(NegativeResponseCode.german(0x40) == "reserviert")
        #expect(NegativeResponseCode.german(0xFE) == "unbekannter Code")
    }

    @Test func durationConvertsToWholeMilliseconds() {
        #expect(Duration.milliseconds(1500).wholeMilliseconds == 1500)
        #expect(Duration.seconds(2).wholeMilliseconds == 2000)
        #expect(Duration.microseconds(2500).wholeMilliseconds == 2)
    }
}
