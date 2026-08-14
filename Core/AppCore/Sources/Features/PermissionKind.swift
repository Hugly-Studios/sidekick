/// The system permissions features can require.
///
/// `AppCore` owns the vocabulary; checking and requesting lives in `PermissionsKit`.
public enum PermissionKind: String, Sendable, CaseIterable {
    case accessibility
    case inputMonitoring
    case fullDiskAccess
    case microphone
    case speechRecognition
    case notifications

    nonisolated public var title: String {
        switch self {
        case .accessibility: "Универсальный доступ"
        case .inputMonitoring: "Мониторинг ввода"
        case .fullDiskAccess: "Полный доступ к диску"
        case .microphone: "Микрофон"
        case .speechRecognition: "Распознавание речи"
        case .notifications: "Уведомления"
        }
    }

    /// Deep-link into the matching System Settings pane.
    nonisolated public var settingsURL: String {
        switch self {
        case .accessibility:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        case .inputMonitoring:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
        case .fullDiskAccess:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
        case .microphone:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        case .speechRecognition:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition"
        case .notifications:
            "x-apple.systempreferences:com.apple.preference.notifications"
        }
    }
}
