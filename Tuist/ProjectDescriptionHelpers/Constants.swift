import ProjectDescription

/// Single source of truth for identifiers and build settings shared by every target.
public enum Sidekick {
    public static let appName = "Sidekick"
    public static let organizationName = "Hugly Studios"

    /// Changing this renames every bundle identifier in the project.
    public static let bundleIDPrefix = "com.hugly.sidekick"

    public static let appBundleID = bundleIDPrefix
    public static let helperBundleID = "\(bundleIDPrefix).helper"

    public static let deploymentTargets = DeploymentTargets.macOS("26.0")
    public static let destinations = Destinations.macOS

    public static func bundleID(module: String) -> String {
        "\(bundleIDPrefix).\(module.lowercased())"
    }
}
