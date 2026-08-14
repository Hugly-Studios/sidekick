import AppCore
import Foundation

public final class InMemorySettingsStore: SettingsStore, @unchecked Sendable {
    private let storage: Storage
    private let prefix: String

    public init() {
        self.storage = Storage()
        self.prefix = ""
    }

    private init(storage: Storage, prefix: String) {
        self.storage = storage
        self.prefix = prefix
    }

    public func value<Value: Codable & Sendable>(for key: SettingKey<Value>) -> Value {
        storage.value(for: storageKey(for: key.name), default: key.defaultValue)
    }

    public func set<Value: Codable & Sendable>(_ value: Value, for key: SettingKey<Value>) {
        storage.set(value, for: storageKey(for: key.name))
    }

    public func namespaced(_ namespace: String) -> any SettingsStore {
        InMemorySettingsStore(storage: storage, prefix: storageKey(for: namespace))
    }

    public func inspect(_ name: String) -> String? {
        storage.inspect(storageKey(for: name))
    }

    public func write(_ name: String, value: String) {
        if value == "true" || value == "false" {
            storage.set(value == "true", for: storageKey(for: name))
            return
        }

        if let number = Int(value) {
            storage.set(number, for: storageKey(for: name))
            return
        }

        storage.set(value, for: storageKey(for: name))
    }

    private func storageKey(for name: String) -> String {
        prefix.isEmpty ? name : "\(prefix).\(name)"
    }
}

private final class Storage: @unchecked Sendable {
    private var values: [String: Data] = [:]
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    func value<Value: Codable>(for key: String, default defaultValue: Value) -> Value {
        guard let data = values[key], let decoded = try? decoder.decode(Value.self, from: data)
        else {
            return defaultValue
        }

        return decoded
    }

    func set<Value: Codable>(_ value: Value, for key: String) {
        guard let data = try? encoder.encode(value) else { return }
        values[key] = data
    }

    func inspect(_ key: String) -> String? {
        guard let data = values[key] else { return nil }

        if let value = try? decoder.decode(Bool.self, from: data) {
            return value ? "true" : "false"
        }
        if let value = try? decoder.decode(Int.self, from: data) {
            return String(value)
        }
        if let value = try? decoder.decode(String.self, from: data) {
            return value
        }

        return String(data: data, encoding: .utf8)
    }
}
