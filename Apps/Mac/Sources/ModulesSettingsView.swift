import AppCore
import SwiftUI

/// Enable/disable list built from the feature registry.
struct ModulesSettingsView: View {
    let features: FeatureRegistry

    var body: some View {
        if features.entries.isEmpty {
            ContentUnavailableView(
                "Модулей пока нет",
                systemImage: "square.grid.2x2",
                description: Text("Модули подключаются в AppEnvironment.featureTypes.")
            )
        } else {
            Form {
                ForEach(features.entries) { entry in
                    Section {
                        Toggle(
                            isOn: Binding(
                                get: { entry.isEnabled },
                                set: { isEnabled in
                                    Task { await features.setEnabled(isEnabled, for: entry.id) }
                                }
                            )
                        ) {
                            Label(entry.descriptor.title, systemImage: entry.descriptor.symbolName)
                            Text(entry.descriptor.summary)
                        }

                        if let failure = entry.failure {
                            Label(failure, systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.orange)
                        }

                        if !entry.descriptor.requiredPermissions.isEmpty {
                            LabeledContent("Разрешения") {
                                Text(
                                    entry.descriptor.requiredPermissions
                                        .map(\.title)
                                        .joined(separator: ", ")
                                )
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
        }
    }
}
