// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "MemWatch",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "MemWatchCore", targets: ["MemWatchCore"]),
        .executable(name: "MemWatch", targets: ["MemWatch"])
    ],
    targets: [
        .target(name: "MemWatchCore"),
        .executableTarget(
            name: "MemWatch",
            dependencies: ["MemWatchCore"]
        ),
        .testTarget(
            name: "MemWatchCoreTests",
            dependencies: ["MemWatchCore"]
        )
    ]
)
