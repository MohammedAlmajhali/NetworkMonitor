// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "NetworkMonitor",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "NetworkMonitor", targets: ["NetworkMonitor"])
    ],
    targets: [
        .executableTarget(
            name: "NetworkMonitor",
            dependencies: [],
            path: "Sources"
        )
    ]
)
