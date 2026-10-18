import Testing
@testable import OBDCore

@Suite struct DisplayPrecisionTests {
    @Test func decimalsFollowTheFormulaResolution() {
        #expect(DisplayPrecision.decimals(forPID: 0x05) == 0) // A - 40
        #expect(DisplayPrecision.decimals(forPID: 0x0D) == 0) // A
        #expect(DisplayPrecision.decimals(forPID: 0x04) == 1) // A * 100 / 255
        #expect(DisplayPrecision.decimals(forPID: 0x06) == 1) // A * 100 / 128 - 100
        #expect(DisplayPrecision.decimals(forPID: 0x10) == 2) // (256A + B) / 100
        #expect(DisplayPrecision.decimals(forPID: 0x3C) == 1) // (256A + B) / 10 - 40
        #expect(DisplayPrecision.decimals(forPID: 0x44) == 3) // (256A + B) * 2 / 65536
        #expect(DisplayPrecision.decimals(forPID: 0x5E) == 2) // (256A + B) / 20
    }

    @Test func overridesKeepReadableValues() {
        #expect(DisplayPrecision.decimals(forPID: 0x0C) == 0)
        #expect(DisplayPrecision.decimals(forPID: 0x42) == 2)
        #expect(DisplayPrecision.decimals(forPID: 0xFE) == nil)
    }

    @Test func fixedFormattingDoesNotDropZeros() {
        #expect(MeasuredValue.format(12.6, decimals: 2) == "12,60")
        #expect(MeasuredValue.format(850.25, decimals: 0) == "850")
        #expect(MeasuredValue.format(1234.5, decimals: 1) == "1234,5")
    }
}
