// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "HealthyMac",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "HealthyMac",
            path: "Sources/HealthyMac",
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Security"),
            ]
        )
    ]
)
