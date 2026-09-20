// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DiscogsKit",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "DiscogsKit", targets: ["DiscogsKit"]),
        .executable(name: "discogs-probe", targets: ["discogs-probe"]),
    ],
    targets: [
        .target(name: "DiscogsKit", swiftSettings: [.swiftLanguageMode(.v6)]),
        // Dev-only helpers. Deliberately not a dependency of DiscogsKit: the shipping app reads the
        // token from the Keychain and must never fall back to an environment variable.
        .target(name: "DevSupport", swiftSettings: [.swiftLanguageMode(.v6)]),
        .executableTarget(
            name: "discogs-probe",
            dependencies: ["DiscogsKit", "DevSupport"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "DiscogsKitTests",
            dependencies: ["DiscogsKit", "DevSupport"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
