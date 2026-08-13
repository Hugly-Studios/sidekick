import Foundation
import Testing

@testable import AppCore

struct SettingsStoreTests {
    private func makeStore() -> (UserDefaultsSettingsStore, UserDefaults) {
        let defaults = UserDefaults(suiteName: "sidekick.tests.\(UUID().uuidString)")!
        return (UserDefaultsSettingsStore(defaults: defaults), defaults)
    }

    @Test func returnsDefaultWhenNothingStored() {
        let (store, _) = makeStore()

        #expect(store.value(for: SettingKey("missing", default: 42)) == 42)
    }

    @Test func storesNativeValuesInspectably() {
        let (store, defaults) = makeStore()

        store.set(true, for: SettingKey("enabled", default: false))

        // Written as a native plist value so `defaults read` stays useful.
        #expect(defaults.object(forKey: "enabled") as? Bool == true)
        #expect(store.value(for: SettingKey("enabled", default: false)) == true)
    }

    @Test func roundTripsCodableValues() {
        struct Snapshot: Codable, Sendable, Equatable {
            let name: String
            let count: Int
        }

        let (store, _) = makeStore()
        let key = SettingKey("snapshot", default: Snapshot(name: "", count: 0))
        let value = Snapshot(name: "work", count: 3)

        store.set(value, for: key)

        #expect(store.value(for: key) == value)
    }

    @Test func namespacePrefixesKeys() {
        let (store, defaults) = makeStore()
        let scoped = store.namespaced("features.awake")

        scoped.set(7, for: SettingKey("timeout", default: 0))

        #expect(defaults.object(forKey: "features.awake.timeout") as? Int == 7)
        #expect(store.value(for: SettingKey("timeout", default: 0)) == 0)
    }

    @Test func fallsBackToDefaultOnTypeMismatch() {
        let (store, defaults) = makeStore()
        defaults.set("not a number", forKey: "count")

        #expect(store.value(for: SettingKey("count", default: 5)) == 5)
    }
}
