// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "AtomRGB",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "atomctl", targets: ["atomctl"]),
        .executable(name: "AtomRGBApp", targets: ["AtomRGBApp"])
    ],
    targets: [
        .target(name: "AtomProtocol"),
        .target(
            name: "HIDTransport",
            dependencies: ["AtomProtocol"],
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("CoreFoundation")
            ]
        ),
        .executableTarget(
            name: "atomctl",
            dependencies: ["HIDTransport"]
        ),
        .executableTarget(
            name: "AtomRGBApp",
            dependencies: ["AtomProtocol", "HIDTransport"]
        ),
        .testTarget(
            name: "AtomProtocolTests",
            dependencies: ["AtomProtocol"]
        ),
        .testTarget(
            name: "HIDTransportTests",
            dependencies: ["AtomProtocol", "HIDTransport"]
        )
    ]
)
