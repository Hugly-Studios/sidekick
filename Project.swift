import ProjectDescription
import ProjectDescriptionHelpers

let project = Project(
    name: Sidekick.appName,
    organizationName: Sidekick.organizationName,
    settings: .settings(
        base: [
            "SWIFT_VERSION": "6.0",
            "MARKETING_VERSION": "0.1.0",
            "CURRENT_PROJECT_VERSION": "1",
        ],
        configurations: [
            .debug(name: "Debug", xcconfig: "Config/Signing.xcconfig"),
            .release(name: "Release", xcconfig: "Config/Signing.xcconfig"),
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
            sources: ["Apps/Mac/Sources/**"],
            dependencies: [
                .target(name: "AppCore"),
                .target(name: "HotkeysKit"),
            ],
            settings: .settings(base: [
                // Indirection through Config/Signing.xcconfig so a gitignored
                // local file can pin a stable identity per machine.
                "CODE_SIGN_STYLE": "$(SIDEKICK_CODE_SIGN_STYLE)",
                "CODE_SIGN_IDENTITY": "$(SIDEKICK_CODE_SIGN_IDENTITY)",
                "DEVELOPMENT_TEAM": "$(SIDEKICK_DEVELOPMENT_TEAM)",
            ])
        )
    ]
        + Module.core("AppCore")
        + Module.core("PrivateAPI")
        + Module.core(
            "HotkeysKit",
            dependencies: [.external(name: "KeyboardShortcuts")],
            hasTests: false
        ),
    schemes: [
        .scheme(
            name: Sidekick.appName,
            shared: true,
            buildAction: .buildAction(targets: [.target(Sidekick.appName)]),
            testAction: .targets([
                .testableTarget(target: .target("AppCoreTests")),
                .testableTarget(target: .target("PrivateAPITests")),
            ]),
            runAction: .runAction(executable: .target(Sidekick.appName))
        )
    ]
)
