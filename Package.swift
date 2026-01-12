// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "devdug",
    products: [
        .library(name: "DevdugCore", targets: ["DevdugCore"]),
        .executable(name: "devdug", targets: ["DevdugCLI"]),
    ],
    targets: [
        .target(
            name: "DevdugCore",
            dependencies: []
        ),
        .executableTarget(
            name: "DevdugCLI",
            dependencies: ["DevdugCore"]
        ),
    ]
)
