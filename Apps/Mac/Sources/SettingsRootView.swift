import AppCore
import SwiftUI

struct SettingsRootView: View {
    let environment: AppEnvironment

    @State private var selection: Section

    init(environment: AppEnvironment) {
        self.environment = environment

        let stored = Section(storageValue: environment.settings.value(for: Self.selectionKey))
        let isReachable =
            switch stored {
            case .general, .modules: true
            case .feature(let id): environment.features.entry(for: id)?.isEnabled == true
            }

        _selection = State(initialValue: isReachable ? stored : .general)
    }

    enum Section: Hashable {
        case general
        case modules
        case feature(FeatureID)

        var storageValue: String {
            switch self {
            case .general: "general"
            case .modules: "modules"
            case .feature(let id): "feature:\(id.rawValue)"
            }
        }

        init(storageValue: String) {
            switch storageValue {
            case "modules":
                self = .modules
            case let value where value.hasPrefix("feature:"):
                self = .feature(FeatureID(rawValue: String(value.dropFirst("feature:".count))))
            default:
                self = .general
            }
        }
    }

    private static let selectionKey = SettingKey(
        "settings.selection",
        default: Section.general.storageValue
    )

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Label("Общие", systemImage: "gearshape")
                    .tag(Section.general)

                Label("Модули", systemImage: "square.grid.2x2")
                    .tag(Section.modules)

                if !enabledEntries.isEmpty {
                    SwiftUI.Section("Включённые модули") {
                        ForEach(enabledEntries) { entry in
                            Label(entry.descriptor.title, systemImage: entry.descriptor.symbolName)
                                .tag(Section.feature(entry.id))
                        }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220)
        } detail: {
            detail
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(minWidth: 720, minHeight: 440)
        .onChange(of: selection) { _, newValue in
            environment.settings.set(newValue.storageValue, for: Self.selectionKey)
        }
    }

    private var enabledEntries: [FeatureRegistry.Entry] {
        environment.features.entries.filter(\.isEnabled)
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .general:
            GeneralSettingsView(launchAtLogin: environment.launchAtLogin)
        case .modules:
            ModulesSettingsView(features: environment.features)
        case .feature(let id):
            if let entry = environment.features.entry(for: id) {
                entry.feature.makeSettingsView()
            } else {
                ContentUnavailableView("Модуль недоступен", systemImage: "questionmark.circle")
            }
        }
    }
}
