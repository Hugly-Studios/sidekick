import SwiftUI

struct SoundsSettingsView: View {
    let feature: SoundsFeature

    var body: some View {
        Form {
            currentSection
            recentSection
            filterSection
            notificationSection

            if feature.muteNeedsAudioCapture {
                captureSection
            }
        }
        .formStyle(.grouped)
    }

    private var currentSection: some View {
        Section("Сейчас") {
            if feature.current.isEmpty {
                Text("сейчас никто не играет")
                    .foregroundStyle(.secondary)
            }

            ForEach(feature.current) { source in
                sourceRow(source)
            }
        }
    }

    private var recentSection: some View {
        Section("Недавно") {
            if feature.recent.isEmpty {
                Text("за выбранное окно никто не играл")
                    .foregroundStyle(.secondary)
            }

            ForEach(feature.recent) { source in
                sourceRow(source)
            }
        }
    }

    private var filterSection: some View {
        Section("Список") {
            Toggle(
                "Скрывать системные процессы",
                isOn: Binding(
                    get: { feature.hideSystem },
                    set: { feature.setHideSystem($0) }
                )
            )

            Stepper(value: recentMinutesBinding, in: 1...120) {
                Text("Недавно: \(feature.recentMinutes) мин")
            }
        }
    }

    private var notificationSection: some View {
        Section("Уведомления") {
            Toggle(
                "Сообщать, когда кто-то начал играть",
                isOn: Binding(
                    get: { feature.notifyOnStart },
                    set: { feature.setNotifyOnStart($0) }
                )
            )
        }
    }

    private var captureSection: some View {
        Section("Запись системного звука") {
            Text(
                "Чтобы замьютить одно приложение, macOS просит разрешение на запись системного звука. Sidekick его не записывает — только глушит выбранный процесс."
            )
            .font(.callout)
            .foregroundStyle(.secondary)

            Button("Открыть настройки доступа") {
                feature.openAudioCaptureSettings()
            }
        }
    }

    @ViewBuilder
    private func sourceRow(_ source: OutputSource) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(feature.title(for: source))
            Text(detail(source))
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack {
                if SystemAudioIdentity.allowsMute(source.bundleID) {
                    if feature.mutedBundleIDs.contains(source.bundleID) {
                        Button("Включить звук") {
                            _ = feature.unmute(bundleID: source.bundleID)
                        }
                    } else {
                        Button("Замьютить") {
                            Task { _ = await feature.mute(bundleID: source.bundleID) }
                        }
                    }
                }

                if !source.bundleID.isEmpty {
                    Button("Открыть") {
                        feature.activateApp(bundleID: source.bundleID)
                    }
                }

                if SystemAudioIdentity.allowsQuit(source.bundleID) {
                    Button("Закрыть", role: .destructive) {
                        _ = feature.quit(bundleID: source.bundleID)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func detail(_ source: OutputSource) -> String {
        let device = source.deviceName.isEmpty ? nil : source.deviceName
        return [device, feature.relativeDescription(for: source)]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    private var recentMinutesBinding: Binding<Int> {
        Binding(
            get: { feature.recentMinutes },
            set: { feature.setRecentMinutes($0) }
        )
    }
}
