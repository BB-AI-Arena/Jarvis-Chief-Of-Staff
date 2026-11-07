// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "Jarvis", platforms: [.macOS(.v14)], targets: [.executableTarget(name: "Jarvis", swiftSettings: [.swiftLanguageMode(.v5)])])
