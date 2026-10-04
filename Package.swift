// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Canteiro",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(name: "Canteiro", targets: ["Canteiro"])
    ],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "6.2.0")
    ],
    targets: [
        .executableTarget(
            name: "Canteiro",
            dependencies: ["Yams"],
            path: "Sources/Canteiro"
        ),
        .testTarget(
            name: "CanteiroTests",
            dependencies: ["Canteiro"],
            path: "Tests/CanteiroTests"
        )
    ]
)
