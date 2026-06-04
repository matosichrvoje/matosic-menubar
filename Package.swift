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
            path: "Sources/MatosicMenubar",
            resources: [
                // Bird PDF is the menubar icon. Bundling it as an SPM
                // resource lets `swift run` find it via Bundle.module —
                // otherwise NSImage(named:) misses (no .app bundle) and
                // the icon silently falls back. The same bundle is
                // copied into the .app by build.sh.
                .process("Resources"),
            ]
        ),
    ]
)
