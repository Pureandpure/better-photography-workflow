// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BetterPhotographyWorkflow",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "BPWDesktop", targets: ["BPWDesktop"])
    ],
    targets: [
        .executableTarget(name: "BPWDesktop"),
        .testTarget(name: "BPWDesktopTests", dependencies: ["BPWDesktop"])
    ]
)
