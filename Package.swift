// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Tosho",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "Tosho",
            targets: ["Tosho"]
        ),
    ],
    dependencies: [
        // Dependencies will be added in future phases
        // For example:
        // .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.16"),
        // .package(url: "https://github.com/abbeycode/UnrarKit.git", from: "2.10.5"),
    ],
    targets: [
        .executableTarget(
            name: "Tosho",
            dependencies: [
                // Dependencies will be added here
            ],
            path: "Tosho",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "ToshoTests",
            dependencies: ["Tosho"],
            path: "Tests"
        ),
    ]
)