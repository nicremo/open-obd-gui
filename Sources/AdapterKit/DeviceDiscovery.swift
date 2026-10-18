import Foundation
import IOKit
import IOKit.serial

public struct SerialDeviceCandidate: Sendable, Codable, Equatable {
    public var path: String
    public var vendorID: Int?
    public var productID: Int?
    public var productName: String?
    public var vendorName: String?
    public var serialNumber: String?
    public var rank: Int
    public var reason: String

    public var isLikelyOBDAdapter: Bool { rank >= 50 }
}

/// Finds serial ports through IOKit and ranks them by how likely they are an OBD adapter.
public enum DeviceDiscovery {
    public struct RawDevice: Sendable, Equatable {
        public var path: String
        public var vendorID: Int?
        public var productID: Int?
        public var productName: String?
        public var vendorName: String?
        public var serialNumber: String?

        public init(path: String, vendorID: Int?, productID: Int?, productName: String?, vendorName: String?, serialNumber: String?) {
            self.path = path
            self.vendorID = vendorID
            self.productID = productID
            self.productName = productName
            self.vendorName = vendorName
            self.serialNumber = serialNumber
        }
    }

    static let hiddenFragments = ["bluetooth-incoming-port", "debug-console", "wlan-debug"]
    static let usbSerialVendors: Set<Int> = [0x067B, 0x10C4, 0x1A86]

    public static func candidates() -> [SerialDeviceCandidate] {
        listSerialServices()
            .compactMap(rank)
            .sorted { $0.rank > $1.rank || ($0.rank == $1.rank && $0.path < $1.path) }
    }

    public static func rank(_ device: RawDevice) -> SerialDeviceCandidate? {
        let path = device.path.lowercased()
        guard !hiddenFragments.contains(where: path.contains) else { return nil }
        let names = [device.productName, device.vendorName].compactMap { $0 }.joined(separator: " ")
        let rank: Int
        let reason: String
        if names.localizedCaseInsensitiveContains("obdlink") || names.localizedCaseInsensitiveContains("obd solutions") {
            (rank, reason) = (100, "OBDLink erkannt")
        } else if device.vendorID == 0x0403 {
            (rank, reason) = (80, "FTDI-USB-Seriell, der OBDLink EX nutzt FTDI")
        } else if let vendor = device.vendorID, usbSerialVendors.contains(vendor) {
            (rank, reason) = (50, "USB-Seriell-Wandler")
        } else if device.vendorID != nil {
            (rank, reason) = (30, "anderes USB-Seriell-Gerät")
        } else if path.contains("obd") {
            (rank, reason) = (40, "Bluetooth-OBD-Adapter, in Version 1 nicht unterstützt")
        } else {
            return nil
        }
        return SerialDeviceCandidate(path: device.path, vendorID: device.vendorID, productID: device.productID,
                                     productName: device.productName, vendorName: device.vendorName,
                                     serialNumber: device.serialNumber, rank: rank, reason: reason)
    }

    static func listSerialServices() -> [RawDevice] {
        guard let matching = IOServiceMatching(kIOSerialBSDServiceValue) else { return [] }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }
        var devices: [RawDevice] = []
        var service = IOIteratorNext(iterator)
        while service != 0 {
            if let device = device(for: service) {
                devices.append(device)
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        return devices
    }

    static func device(for service: io_object_t) -> RawDevice? {
        guard let path = property(service, kIOCalloutDeviceKey, parents: false) as? String else { return nil }
        return RawDevice(
            path: path,
            vendorID: property(service, "idVendor", parents: true) as? Int,
            productID: property(service, "idProduct", parents: true) as? Int,
            productName: (property(service, "USB Product Name", parents: true) ?? property(service, "kUSBProductString", parents: true)) as? String,
            vendorName: (property(service, "USB Vendor Name", parents: true) ?? property(service, "kUSBVendorString", parents: true)) as? String,
            serialNumber: (property(service, "USB Serial Number", parents: true) ?? property(service, "kUSBSerialNumberString", parents: true)) as? String
        )
    }

    static func property(_ service: io_object_t, _ key: String, parents: Bool) -> CFTypeRef? {
        if parents {
            return IORegistryEntrySearchCFProperty(service, kIOServicePlane, key as CFString, kCFAllocatorDefault,
                                                   IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents))
        }
        return IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }
}
