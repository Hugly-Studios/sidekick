import Foundation

/// A typed settings key with its default value.
public struct SettingKey<Value: Codable & Sendable>: Sendable {
    public let name: String
    public let defaultValue: Value

    public init(_ name: String, default defaultValue: Value) {
        self.name = name
        self.defaultValue = defaultValue
    }
}

public protocol SettingsStore: Sendable {
    func value<Value: Codable & Sendable>(for key: SettingKey<Value>) -> Value
    func set<Value: Codable & Sendable>(_ value: Value, for key: SettingKey<Value>)

    /// A view of the same storage with keys prefixed, used to isolate features.
    func namespaced(_ namespace: String) -> any SettingsStore

    /// Untyped access for the CLI. Values are stored as Bool, Int or String.
    func inspect(_ name: String) -> String?
    func write(_ name: String, value: String)
}

/// `UserDefaults`-backed store.
///
/// Values that `UserDefaults` understands natively are written as-is so the
/// state stays inspectable with `defaults read`; anything else is JSON encoded.
public struct UserDefaultsSettingsStore: SettingsStore {
    // UserDefaults is thread-safe but not marked Sendable.
    nonisolated(unsafe) private let defaults: UserDefaults
    private let prefix: String

    public init(defaults: UserDefaults = .standard, prefix: String = "") {
        self.defaults = defaults
        self.prefix = prefix
    }

    public func value<Value: Codable & Sendable>(for key: SettingKey<Value>) -> Value {
        guard let stored = defaults.object(forKey: storageKey(for: key.name)) else {
            return key.defaultValue
        }

        if let typed = stored as? Value {
            return typed
        }

        if let data = stored as? Data,
            let decoded = try? JSONDecoder().decode(Value.self, from: data)
        {
            return decoded
        }

        return key.defaultValue
    }

    public func set<Value: Codable & Sendable>(_ value: Value, for key: SettingKey<Value>) {
        let storageKey = storageKey(for: key.name)

        if isNativelyStorable(value) {
            defaults.set(value, forKey: storageKey)
            return
        }

        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: storageKey)
    }

    public func namespaced(_ namespace: String) -> any SettingsStore {
        UserDefaultsSettingsStore(defaults: defaults, prefix: storageKey(for: namespace))
    }

    public func inspect(_ name: String) -> String? {
        guard let stored = defaults.object(forKey: storageKey(for: name)) else { return nil }

        switch stored {
        case let value as Bool:
            return value ? "true" : "false"
        case let value as Int:
            return String(value)
        case let value as Double:
            return String(value)
        case let value as String:
            return value
        default:
            return String(describing: stored)
        }
    }

    public func write(_ name: String, value: String) {
        let key = storageKey(for: name)

        if value == "true" || value == "false" {
            defaults.set(value == "true", forKey: key)
            return
        }

        if let number = Int(value) {
            defaults.set(number, forKey: key)
            return
        }

        defaults.set(value, forKey: key)
    }

    private func storageKey(for name: String) -> String {
        prefix.isEmpty ? name : "\(prefix).\(name)"
    }

    private func isNativelyStorable(_ value: some Any) -> Bool {
        switch value {
        case is Bool, is Int, is Double, is String, is Data, is Date:
            true
        default:
            false
        }
    }
}
