import ProjectDescription

/// Target factories so every module in the project is described the same way.
///
/// A core module lives in `Core/<Name>` and is shared infrastructure.
/// A feature module lives in `Features/<Name>` and implements one user-facing capability.
public enum Module {
    public enum Isolation: String {
        case mainActor = "MainActor"
        case nonisolated = "nonisolated"
    }

    public static func core(
        _ name: String,
        dependencies: [TargetDependency] = [],
        testDependencies: [TargetDependency] = [],
        hasTests: Bool = true,
        isolation: Isolation = .nonisolated
    ) -> [Target] {
        module(
            name,
            folder: "Core",
            dependencies: dependencies,
            testDependencies: testDependencies,
            hasTests: hasTests,
            isolation: isolation
        )
    }

    public static func feature(
        _ name: String,
        dependencies: [TargetDependency] = [],
        testDependencies: [TargetDependency] = [],
        hasTests: Bool = true
    ) -> [Target] {
        module(
            name,
            folder: "Features",
            dependencies: [.target(name: "AppCore")] + dependencies,
            testDependencies: testDependencies,
            hasTests: hasTests,
            isolation: .mainActor
        )
    }

    public static func testSupport(
        _ name: String,
        dependencies: [TargetDependency] = []
    ) -> [Target] {
        [
            Target.target(
                name: name,
                destinations: Sidekick.destinations,
                product: .staticFramework,
                bundleId: Sidekick.bundleID(module: name),
                deploymentTargets: Sidekick.deploymentTargets,
                infoPlist: .default,
                buildableFolders: [.folder("Core/\(name)/Sources")],
                dependencies: dependencies,
                settings: .settings(base: compilerSettings(isolation: .nonisolated))
            )
        ]
    }

    private static func module(
        _ name: String,
        folder: String,
        dependencies: [TargetDependency],
        testDependencies: [TargetDependency],
        hasTests: Bool,
        isolation: Isolation
    ) -> [Target] {
        let target = Target.target(
            name: name,
            destinations: Sidekick.destinations,
            product: .staticFramework,
            bundleId: Sidekick.bundleID(module: name),
            deploymentTargets: Sidekick.deploymentTargets,
            infoPlist: .default,
            buildableFolders: [.folder("\(folder)/\(name)/Sources")],
            dependencies: dependencies,
            settings: .settings(base: compilerSettings(isolation: isolation))
        )

        guard hasTests else { return [target] }

        let tests = Target.target(
            name: "\(name)Tests",
            destinations: Sidekick.destinations,
            product: .unitTests,
            bundleId: Sidekick.bundleID(module: "\(name)Tests"),
            deploymentTargets: Sidekick.deploymentTargets,
            infoPlist: .default,
            buildableFolders: [.folder("\(folder)/\(name)/Tests")],
            dependencies: [.target(name: name)] + testDependencies,
            settings: .settings(base: compilerSettings(isolation: isolation))
        )

        return [target, tests]
    }

    public static func compilerSettings(isolation: Isolation) -> SettingsDictionary {
        [
            "SWIFT_APPROACHABLE_CONCURRENCY": "YES",
            "SWIFT_DEFAULT_ACTOR_ISOLATION": .string(isolation.rawValue),
            "ENABLE_HARDENED_RUNTIME": "YES",
        ]
    }
}
