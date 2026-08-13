import ProjectDescription

/// Target factories so every module in the project is described the same way.
///
/// A core module lives in `Core/<Name>` and is shared infrastructure.
/// A feature module lives in `Features/<Name>` and implements one user-facing capability.
public enum Module {
    public static func core(
        _ name: String,
        dependencies: [TargetDependency] = [],
        hasTests: Bool = true
    ) -> [Target] {
        module(name, folder: "Core", dependencies: dependencies, hasTests: hasTests)
    }

    public static func feature(
        _ name: String,
        dependencies: [TargetDependency] = [],
        hasTests: Bool = true
    ) -> [Target] {
        module(
            name,
            folder: "Features",
            dependencies: [.target(name: "AppCore")] + dependencies,
            hasTests: hasTests
        )
    }

    private static func module(
        _ name: String,
        folder: String,
        dependencies: [TargetDependency],
        hasTests: Bool
    ) -> [Target] {
        let target = Target.target(
            name: name,
            destinations: Sidekick.destinations,
            product: .staticFramework,
            bundleId: Sidekick.bundleID(module: name),
            deploymentTargets: Sidekick.deploymentTargets,
            infoPlist: .default,
            sources: ["\(folder)/\(name)/Sources/**"],
            dependencies: dependencies
        )

        guard hasTests else { return [target] }

        let tests = Target.target(
            name: "\(name)Tests",
            destinations: Sidekick.destinations,
            product: .unitTests,
            bundleId: Sidekick.bundleID(module: "\(name)Tests"),
            deploymentTargets: Sidekick.deploymentTargets,
            infoPlist: .default,
            sources: ["\(folder)/\(name)/Tests/**"],
            dependencies: [.target(name: name)]
        )

        return [target, tests]
    }
}
