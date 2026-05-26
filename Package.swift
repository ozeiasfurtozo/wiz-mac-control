// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "WiZLightBar",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "WiZLightBar", targets: ["WiZLightBar"])
    ],
    targets: [
        .executableTarget(
            name: "WiZLightBar"
        )
    ]
)
