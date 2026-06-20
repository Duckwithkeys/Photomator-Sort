// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "PhotomatorSort",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "PhotomatorSort", targets: ["PhotomatorSort"])
    ],
    targets: [
        .executableTarget(
            name: "PhotomatorSort",
            path: "PhotomatorSort",
            resources: [
                .process("Resources")
            ]
        )
    ]
)
