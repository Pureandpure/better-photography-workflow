// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "BPWEngine", platforms: [.macOS(.v14)], products: [.executable(name: "bpw-engine", targets: ["BPWEngine"])], targets: [.target(name: "BPWCore"), .executableTarget(name: "BPWEngine", dependencies: ["BPWCore"]), .testTarget(name: "BPWCoreTests", dependencies: ["BPWCore"])])
