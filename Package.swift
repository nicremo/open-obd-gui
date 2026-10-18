// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "OpenOBD",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "OBDCore", targets: ["OBDCore"]),
        .library(name: "AdapterKit", targets: ["AdapterKit"]),
        .library(name: "VehicleSim", targets: ["VehicleSim"]),
        .library(name: "FordKnowledge", targets: ["FordKnowledge"]),
        .library(name: "DiagnosticEngine", targets: ["DiagnosticEngine"]),
        .library(name: "CLIKit", targets: ["CLIKit"]),
        .library(name: "OpenOBDAppCore", targets: ["OpenOBDAppCore"]),
        .executable(name: "openobd", targets: ["OpenOBDCLI"]),
        .executable(name: "OpenOBDApp", targets: ["OpenOBDApp"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.6.2"),
    ],
    targets: [
        .target(name: "OBDCore"),
        .testTarget(name: "OBDCoreTests", dependencies: ["OBDCore"]),
        .target(name: "AdapterKit", dependencies: ["OBDCore"], linkerSettings: [.linkedFramework("IOKit")]),
        .testTarget(name: "AdapterKitTests", dependencies: ["AdapterKit"]),
        .target(name: "VehicleSim", dependencies: ["OBDCore", "AdapterKit"]),
        .testTarget(name: "VehicleSimTests", dependencies: ["VehicleSim"]),
        .target(name: "FordKnowledge", dependencies: ["OBDCore"], resources: [.process("Resources")]),
        .testTarget(name: "FordKnowledgeTests", dependencies: ["FordKnowledge"]),
        .target(name: "DiagnosticEngine", dependencies: ["OBDCore", "AdapterKit", "FordKnowledge"]),
        .testTarget(name: "DiagnosticEngineTests", dependencies: ["DiagnosticEngine", "VehicleSim"]),
        .target(name: "CLIKit", dependencies: [
            "OBDCore", "AdapterKit", "VehicleSim", "FordKnowledge", "DiagnosticEngine",
            .product(name: "ArgumentParser", package: "swift-argument-parser"),
        ]),
        .testTarget(name: "CLIKitTests", dependencies: ["CLIKit"]),
        .executableTarget(name: "OpenOBDCLI", dependencies: ["CLIKit"]),
        .target(name: "OpenOBDAppCore", dependencies: ["OBDCore", "AdapterKit", "VehicleSim", "FordKnowledge", "DiagnosticEngine"]),
        .testTarget(name: "OpenOBDAppCoreTests", dependencies: ["OpenOBDAppCore"]),
        .executableTarget(name: "OpenOBDApp", dependencies: ["OpenOBDAppCore"]),
    ]
)
