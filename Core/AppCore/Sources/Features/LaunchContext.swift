/// How this run of the app started.
///
/// Features behave differently at login: restoring a layout automatically is
/// wanted then, but doing it when the user opens the app by hand would throw
/// their current windows around.
public struct LaunchContext: Sendable {
    public let isLoginLaunch: Bool

    public init(isLoginLaunch: Bool) {
        self.isLoginLaunch = isLoginLaunch
    }
}
