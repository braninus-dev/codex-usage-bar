// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CodexUsage",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "UsageCore", targets: ["UsageCore"]),
        .executable(name: "CodexUsage", targets: ["CodexUsage"]),
    ],
    targets: [
        .target(name: "UsageCore"),
        .executableTarget(name: "CodexUsage", dependencies: ["UsageCore"], resources: [.process("Resources")]),
        .executableTarget(name: "UsageCoreChecks", dependencies: ["UsageCore"]),
    ],
    swiftLanguageVersions: [.v5]
)
