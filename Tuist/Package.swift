// swift-tools-version: 6.0
import PackageDescription

#if TUIST
import ProjectDescription

let packageSettings = PackageSettings(
    baseSettings: .settings(base: ["SWIFT_VERSION": "6.0"])
)
#endif

let package = Package(
    name: "SidekickDependencies",
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "3.0.1")
    ]
)
