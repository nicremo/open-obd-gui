import Foundation
import OBDCore

extension VehicleProfile {
    /// Synthetic VIN, `SM` marks the simulator.
    public static let focusVIN = "WF0NXXGCHNSM67890"

    /// Synthetic Ford Focus Mk4 1.5 EcoBoost: gasoline readiness, gateway, all modules on HS-CAN, MS-CAN empty.
    public static let focusMk4 = VehicleProfile(
        id: "focus-mk4",
        title: "Ford Focus Mk4 1.5 EcoBoost (Simulator)",
        note: "Synthetisches Profil. Struktur plausibel, Werte erfunden.",
        batteryVoltage: 12.5,
        ecus: [
            VirtualECU(
                name: "PCM", request: 0x7E0, bus: .hsCAN, answersOBD: true,
                pids: [
                    0x01: .constant([0x00, 0x07, 0x65, 0x00]),
                    0x04: .wave(12, 48, period: 8, encode: SimEncode.percent),
                    0x05: .wave(88, 94, period: 90, encode: SimEncode.temperature),
                    0x06: .wave(-3, 3, period: 4, encode: SimEncode.trim),
                    0x07: .constant([0x82]),
                    0x0B: .wave(30, 120, period: 8, encode: SimEncode.plain),
                    0x0C: .wave(720, 3200, period: 8, encode: SimEncode.rpm),
                    0x0D: .wave(0, 95, period: 25, encode: SimEncode.plain),
                    0x0E: .wave(4, 24, period: 8, encode: SimEncode.timing),
                    0x0F: .constant([0x3F]),
                    0x10: .wave(3, 38, period: 8, encode: SimEncode.airflow),
                    0x11: .wave(12, 60, period: 8, encode: SimEncode.percent),
                    0x13: .constant([0x03]),
                    0x14: .wave(0.1, 0.85, period: 2, encode: { SimEncode.byte($0 * 200) + [0x80] }),
                    0x15: .constant([0x50, 0xFF]),
                    0x1C: .constant([0x06]),
                    0x1F: .constant([0x01, 0x2C]),
                    0x21: .constant([0x00, 0x00]),
                    0x2F: .constant([0x9E]),
                    0x30: .constant([0x28]),
                    0x31: .constant([0x0F, 0xA0]),
                    0x33: .constant([0x61]),
                    0x3C: .wave(420, 620, period: 30, encode: SimEncode.catalyst),
                    0x42: .wave(14.0, 14.4, period: 20, encode: SimEncode.voltage),
                    0x44: .constant([0x80, 0x00]),
                    0x46: .constant([0x37]),
                    0x49: .wave(10, 45, period: 8, encode: SimEncode.percent),
                    0x51: .constant([0x01]),
                    0xA6: .constant([0x00, 0x05, 0x7E, 0x40]),
                ],
                vehicleInfo: [
                    0x02: [0x01] + ascii(focusVIN),
                    0x04: [0x01] + ascii("SIM2-12A650-BA\0\0"),
                    0x06: [0x01, 0x0B, 0xAD, 0xF0, 0x0D],
                    0x0A: [0x01] + ascii("ECM-EngineControl\0\0\0"),
                ],
                dids: [0xF190: ascii(focusVIN), 0xF111: ascii("SIM2-12A650-BA"), 0xF188: ascii("SIM2-14C204-BA")]
            ),
            VirtualECU(name: "GWM", request: 0x716, bus: .hsCAN, dids: [0xF190: ascii(focusVIN), 0xF111: ascii("SIM2-14F642-AA")]),
            VirtualECU(name: "ABS", request: 0x760, bus: .hsCAN, dids: [0xF190: ascii(focusVIN), 0xF111: ascii("SIM2-2C219-BA")]),
            VirtualECU(name: "RCM", request: 0x737, bus: .hsCAN, dids: [0xF190: ascii(focusVIN), 0xF111: ascii("SIM2-14B321-BA")]),
            VirtualECU(name: "IPC", request: 0x720, bus: .hsCAN, dids: [0xF190: ascii(focusVIN), 0xF111: ascii("SIM2-10849-BA")]),
            VirtualECU(name: "BCM", request: 0x726, bus: .hsCAN, dids: [0xF190: ascii(focusVIN), 0xF111: ascii("SIM2-14A067-BA")]),
            VirtualECU(name: "PSCM", request: 0x730, bus: .hsCAN, dids: [0xF111: ascii("SIM2-3D725-BA")]),
            VirtualECU(name: "APIM", request: 0x7D0, bus: .hsCAN, dids: [0xF111: ascii("SIM2-14G371-BA")]),
            VirtualECU(
                name: "IPMA", request: 0x706, bus: .hsCAN,
                dids: [0xF111: ascii("SIM2-19H406-BA")],
                dtcs: [UDSDTC(code: DTCCode(raw: 0xF003), failureType: 0x16, status: DTCStatus(rawValue: 0x28))]
            ),
        ]
    )
}
