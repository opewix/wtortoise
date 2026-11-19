// swift-tools-version:5.9
import PackageDescription

// Расширение Finder (Sources/WTortoiseFinder) собирает scripts/bundle.sh напрямую через swiftc:
// ему нужна точка входа NSExtensionMain, которую SwiftPM не умеет.
let package = Package(
    name: "WTortoise",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "WTortoise", path: "Sources/WTortoise")
    ]
)
