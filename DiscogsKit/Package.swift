// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "DiscogsKit",
    platforms: [.macOS(.v26), .iOS(.v26)],
    products: [
        .library(name: "DiscogsKit", targets: ["DiscogsKit"]),
    ],
    targets: [
        .target(name: "DiscogsKit", swiftSettings: [.swiftLanguageMode(.v6)]),
        .testTarget(
            name: "DiscogsKitTests",
            dependencies: ["DiscogsKit"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
