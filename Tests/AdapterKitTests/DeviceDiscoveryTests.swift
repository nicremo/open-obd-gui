import Testing
@testable import AdapterKit

@Suite struct DeviceDiscoveryTests {
    func device(_ path: String, vendor: Int? = nil, product: String? = nil, maker: String? = nil) -> DeviceDiscovery.RawDevice {
        DeviceDiscovery.RawDevice(path: path, vendorID: vendor, productID: nil, productName: product, vendorName: maker, serialNumber: nil)
    }

    @Test func obdLinkByNameRanksHighest() throws {
        let candidate = try #require(DeviceDiscovery.rank(device("/dev/cu.usbserial-A1", vendor: 0x0403, product: "OBDLink EX")))
        #expect(candidate.rank == 100)
        #expect(candidate.isLikelyOBDAdapter)
    }

    @Test func ftdiWithoutNameIsLikely() throws {
        let candidate = try #require(DeviceDiscovery.rank(device("/dev/cu.usbserial-A1", vendor: 0x0403, product: "FT231X USB UART")))
        #expect(candidate.rank == 80)
    }

    @Test func otherUSBSerialChipsAreCandidates() throws {
        #expect(DeviceDiscovery.rank(device("/dev/cu.usbserial-1", vendor: 0x067B))?.rank == 50)
        #expect(DeviceDiscovery.rank(device("/dev/cu.usbmodem1", vendor: 0x1234))?.rank == 30)
        #expect(DeviceDiscovery.rank(device("/dev/cu.usbmodem1", vendor: 0x1234))?.isLikelyOBDAdapter == false)
    }

    @Test func bluetoothAudioAndDebugPortsAreHidden() {
        #expect(DeviceDiscovery.rank(device("/dev/cu.Bluetooth-Incoming-Port")) == nil)
        #expect(DeviceDiscovery.rank(device("/dev/cu.debug-console")) == nil)
        #expect(DeviceDiscovery.rank(device("/dev/cu.JBLFlip5")) == nil)
    }

    @Test func bluetoothOBDPortIsShownButNotPreferred() throws {
        let candidate = try #require(DeviceDiscovery.rank(device("/dev/cu.OBDLinkMX")))
        #expect(candidate.rank == 40)
    }

    @Test func systemEnumerationRuns() {
        let candidates = DeviceDiscovery.candidates()
        #expect(candidates.allSatisfy { $0.path.hasPrefix("/dev/cu.") })
        #expect(candidates.allSatisfy { !$0.path.contains("Bluetooth-Incoming-Port") })
        #expect(candidates == candidates.sorted { $0.rank > $1.rank || ($0.rank == $1.rank && $0.path < $1.path) })
    }
}
