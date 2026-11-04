// swift-tools-version: 6.4
import PackageDescription

// The macOS app links SwiftUI, CoreBluetooth, and IOBluetooth. Those frameworks
// are not in the Linux toolchain, so the manifest compiled on Linux publishes
// only the portable core. On macOS the app target is part of the package.
#if os(macOS)
let personifyPlatforms: [SupportedPlatform] = [.macOS(.v14)]
let personifyProducts: [Product] = [
    .library(name: "PersonifyCore", targets: ["PersonifyCore"]),
    .executable(name: "PersonifyDesk", targets: ["PersonifyDesk"]),
]
let personifyTargets: [Target] = [
    .target(name: "PersonifyCore"),
        .target(
            name: "PairingBridge",
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("include"),
            ],
            linkerSettings: [
            .linkedFramework("IOBluetooth"),
            .linkedFramework("IOKit"),
        ]
    ),
    .executableTarget(
        name: "PersonifyDesk",
        dependencies: ["PersonifyCore", "PairingBridge"],
        linkerSettings: [
            .linkedFramework("CoreBluetooth"),
            .linkedFramework("SwiftUI"),
            .linkedFramework("AppKit"),
            .linkedFramework("Security"),
        ]
    ),
    .testTarget(name: "PersonifyCoreTests", dependencies: ["PersonifyCore"], exclude: ["Fixtures"]),
]
#else
let personifyProducts: [Product] = [
    .library(name: "PersonifyCore", targets: ["PersonifyCore"]),
]
let personifyTargets: [Target] = [
    .target(name: "PersonifyCore"),
    .testTarget(name: "PersonifyCoreTests", dependencies: ["PersonifyCore"], exclude: ["Fixtures"]),
]
#endif

#if os(macOS)
let package = Package(
    name: "PersonifyDesk",
    platforms: personifyPlatforms,
    products: personifyProducts,
    targets: personifyTargets
)
#else
let package = Package(
    name: "PersonifyDesk",
    products: personifyProducts,
    targets: personifyTargets
)
#endif
