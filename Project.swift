import ProjectDescription
import ProjectDescriptionHelpers

let project = Project(
    name: Sidekick.appName,
    organizationName: Sidekick.organizationName,
    settings: .settings(
        base: [
            "SWIFT_VERSION": "6.2",
            "SWIFT_APPROACHABLE_CONCURRENCY": "YES",
            "ENABLE_HARDENED_RUNTIME": "YES",
        ],
        configurations: [
            .debug(
                name: "Debug",
                xcconfig: "Config/Signing.xcconfig"
            ),
            .release(
                name: "Release",
                xcconfig: "Config/Signing.xcconfig"
            ),
        ]
    ),
    targets: [
        .target(
            name: Sidekick.appName,
            destinations: Sidekick.destinations,
            product: .app,
            bundleId: Sidekick.appBundleID,
            deploymentTargets: Sidekick.deploymentTargets,
            infoPlist: .extendingDefault(with: [
                // Menu bar app: no Dock icon, no main window.
                "LSUIElement": true,
                "LSApplicationCategoryType": "public.app-category.productivity",
                "CFBundleDisplayName": .string(Sidekick.appName),
                "CFBundleShortVersionString": "$(MARKETING_VERSION)",
                "CFBundleVersion": "$(CURRENT_PROJECT_VERSION)",
                "NSHumanReadableCopyright": .string("© \(Sidekick.organizationName)"),
            ]),
            buildableFolders: ["Apps/Mac/Sources"],
            copyFiles: [
                .wrapper(
                    name: "Embed Launch Agent",
                    subpath: "Contents/Library/LaunchAgents",
                    files: ["Apps/Mac/LaunchAgents/com.hugly.sidekick.login.plist"]
                )
            ],
            dependencies: [
                .target(name: "AppCore"),
                .target(name: "ControlSurface"),
                .target(name: "HotkeysKit"),
                .target(name: "PermissionsKit"),
                .target(name: "SystemKit"),
                .target(name: "Workspaces"),
            ],
            settings: .settings(
                base: [
                    // Indirection through Config/Signing.xcconfig so a gitignored
                    // local file can pin a stable identity per machine.
                    "CODE_SIGN_STYLE": "$(SIDEKICK_CODE_SIGN_STYLE)",
                    "CODE_SIGN_IDENTITY": "$(SIDEKICK_CODE_SIGN_IDENTITY)",
                    "DEVELOPMENT_TEAM": "$(SIDEKICK_DEVELOPMENT_TEAM)",
                ].merging(Module.compilerSettings(isolation: .mainActor)) { _, new in new }
            )
        )
    ]
        + Module.core(
            "AppCore",
            testDependencies: [.target(name: "TestSupport")],
            isolation: .mainActor
        )
        + Module.core("PrivateAPI")
        + Module.core(
            "HotkeysKit",
            dependencies: [.external(name: "KeyboardShortcuts")],
            hasTests: false,
            isolation: .mainActor
        )
        + Module.core(
            "Automation",
            dependencies: [.target(name: "PrivateAPI")],
            hasTests: false
        )
        + Module.core(
            "SystemKit",
            dependencies: [.target(name: "AppCore")]
        )
        + Module.core(
            "PermissionsKit",
            dependencies: [.target(name: "AppCore")]
        )
        + Module.core(
            "ControlSurface",
            dependencies: [
                .target(name: "AppCore"),
                .target(name: "PermissionsKit"),
            ],
            testDependencies: [.target(name: "TestSupport")]
        )
        + Module.testSupport(
            "TestSupport",
            dependencies: [
                .target(name: "AppCore"),
                .target(name: "SystemKit"),
                .target(name: "PermissionsKit"),
            ]
        )
        + Module.feature(
            "Workspaces",
            dependencies: [
                .target(name: "Automation"),
                .target(name: "PrivateAPI"),
            ],
            testDependencies: [.target(name: "TestSupport")]
        ),
    schemes: [
        .scheme(
            name: Sidekick.appName,
            shared: true,
            buildAction: .buildAction(targets: [.target(Sidekick.appName)]),
            testAction: .targets([
                .testableTarget(target: .target("AppCoreTests")),
                .testableTarget(target: .target("PrivateAPITests")),
                .testableTarget(target: .target("SystemKitTests")),
                .testableTarget(target: .target("PermissionsKitTests")),
                .testableTarget(target: .target("ControlSurfaceTests")),
                .testableTarget(target: .target("WorkspacesTests")),
            ]),
            runAction: .runAction(executable: .target(Sidekick.appName))
        )
    ]
)
