// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RedmiBudsControl",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "RedmiBudsControl",
            path: "Sources/RedmiBudsControl",
            swiftSettings: [
                .swiftLanguageMode(.v5),
                .unsafeFlags(["-parse-as-library"])
            ],
            linkerSettings: [
                .linkedFramework("IOBluetooth"),
                .linkedFramework("ServiceManagement")
            ]
        )
    ]
)
