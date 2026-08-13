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

    public var title: String {
        switch self {
        case .accessibility: "Универсальный доступ"
        case .inputMonitoring: "Мониторинг ввода"
        case .fullDiskAccess: "Полный доступ к диску"
        case .microphone: "Микрофон"
        case .speechRecognition: "Распознавание речи"
        case .notifications: "Уведомления"
        }
    }
}
