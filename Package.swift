// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "AtomRGB",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "atomctl", targets: ["atomctl"])
    ],
    targets: [
        .target(
            name: "HIDTransport",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("CoreFoundation")
            ]
        ),
        .executableTarget(
            name: "atomctl",
            dependencies: ["HIDTransport"]
        )
    ]
)
