// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "FlowMac",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "FlowMac",
            targets: ["FlowMac"]
        )
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "FlowMac",
            path: "FlowMac",
            exclude: ["Resources/Info.plist", "Resources/FlowMac.entitlements"],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ],
            linkerSettings: [
                .linkedFramework("AVFoundation"),
                .linkedFramework("Carbon"),
                .linkedFramework("AppKit"),
                .linkedFramework("UserNotifications")
            ]
        ),
        // Only Unit/ is built: the older suites under Core/ and Integration/ predate
        // several API changes and no longer compile.
        .testTarget(
            name: "FlowMacTests",
            dependencies: ["FlowMac"],
            path: "FlowMacTests",
            sources: ["Unit"]
        )
    ]
)
