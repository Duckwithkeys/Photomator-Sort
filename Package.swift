// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "DuckSort",
    platforms: [
        .macOS("26.0")
    ],
    products: [
        .executable(name: "DuckSort", targets: ["DuckSort"])
    ],
    targets: [
        .executableTarget(
            name: "DuckSort",
            path: "DuckSort",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "DuckSortTests",
            dependencies: ["DuckSort"],
            path: "Tests/DuckSortTests"
        )
    ]
)
