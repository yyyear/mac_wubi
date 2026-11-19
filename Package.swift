// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WubiInput",
    platforms: [.macOS(.v12)],
    products: [
        .executable(name: "WubiInput", targets: ["WubiInput"]),
        .executable(name: "wubi-preview", targets: ["WubiPreview"]),
        .executable(name: "wubi-cli", targets: ["WubiCLI"]),
        .library(name: "WubiCore", targets: ["WubiCore"]),
    ],
    targets: [
        .target(
            name: "WubiCore",
            resources: [.copy("Resources/wubi86.bin")]
        ),
        .target(
            name: "WubiUI",
            dependencies: ["WubiCore"],
            resources: [.process("Resources")],
            linkerSettings: [.linkedFramework("Cocoa")]
        ),
        .executableTarget(
            name: "WubiInput",
            dependencies: ["WubiCore", "WubiUI"],
            linkerSettings: [
                .linkedFramework("Cocoa"),
                .linkedFramework("InputMethodKit"),
            ]
        ),
        .executableTarget(
            name: "WubiPreview",
            dependencies: ["WubiCore", "WubiUI"],
            linkerSettings: [.linkedFramework("Cocoa")]
        ),
        .executableTarget(
            name: "WubiCLI",
            dependencies: ["WubiCore"]
        ),
        .testTarget(
            name: "WubiCoreTests",
            dependencies: ["WubiCore"]
        ),
    ]
)