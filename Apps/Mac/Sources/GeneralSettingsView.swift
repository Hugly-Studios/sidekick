import SwiftUI

struct GeneralSettingsView: View {
    let launchAtLogin: LaunchAtLoginController

    var body: some View {
        Form {
            Section {
                Toggle(
                    "Запускать при входе в систему",
                    isOn: Binding(
                        get: { launchAtLogin.isEnabled },
                        set: { launchAtLogin.setEnabled($0) }
                    )
                )

                if let failure = launchAtLogin.failure {
                    Text(failure)
                        .font(.callout)
                        .foregroundStyle(.red)
                }
            } footer: {
                Text("Разрешение выдаётся в «Основные» → «Элементы входа и расширения».")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("О программе") {
                LabeledContent("Версия", value: Self.version)
            }
        }
        .formStyle(.grouped)
        .onAppear { launchAtLogin.refresh() }
    }

    private static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "\(short) (\(build))"
    }
}
