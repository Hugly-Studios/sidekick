/// How a HAL running-output callback becomes start/stop events.
///
/// A short sound can flip `IsRunningOutput` 0→1→0 before we read it. The
/// listener still fires; `allowPulse` records that as a start+stop so the
/// sound is not lost.
enum AudioOutputTransition {
    static func events(
        previousRunning: Bool?,
        currentRunning: Bool,
        allowPulse: Bool
    ) -> [AudioOutputChange.Kind] {
        if currentRunning, previousRunning != true {
            return [.started]
        }
        if !currentRunning, previousRunning == true {
            return [.stopped]
        }
        if !currentRunning, allowPulse {
            return [.started, .stopped]
        }
        return []
    }
}
