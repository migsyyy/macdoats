// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "MacDoats",
    platforms: [.macOS(.v14)],
    targets: [.executableTarget(name: "MacDoats", path: "Sources")]
)
