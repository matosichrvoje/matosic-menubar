// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "MatosicMenubar",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "MatosicMenubar", targets: ["MatosicMenubar"]),
    ],
    targets: [
        .executableTarget(
            name: "MatosicMenubar",
            path: "Sources/MatosicMenubar"
        ),
    ]
)
