import SwiftUI

/// Per-app mute/quit live in this view so shell commands stay generic.
struct SoundsMenuView: View {
    let feature: SoundsFeature

    var body: some View {
        if feature.current.isEmpty {
            Text("сейчас никто не играет")
        } else {
            Text("Сейчас")
            ForEach(feature.current) { source in
                sourceRows(source)
            }
        }

        if !feature.recent.isEmpty {
            Divider()
            Text("Недавно")
            ForEach(feature.recent) { source in
                sourceRows(source)
            }
        }
    }

    @ViewBuilder
    private func sourceRows(_ source: OutputSource) -> some View {
        let name = feature.title(for: source)
        let device = source.deviceName.isEmpty ? "" : " · \(source.deviceName)"
        Text("\(name)\(device) · \(feature.relativeDescription(for: source))")

        if SystemAudioIdentity.allowsMute(source.bundleID) {
            if feature.mutedBundleIDs.contains(source.bundleID) {
                Button("Включить звук \(name)") {
                    _ = feature.unmute(bundleID: source.bundleID)
                }
            } else {
                Button("Замьютить \(name)") {
                    Task { _ = await feature.mute(bundleID: source.bundleID) }
                }
            }
        }

        if !source.bundleID.isEmpty {
            Button("Открыть \(name)") {
                feature.activateApp(bundleID: source.bundleID)
            }
        }

        if SystemAudioIdentity.allowsQuit(source.bundleID) {
            Button("Закрыть \(name)") {
                _ = feature.quit(bundleID: source.bundleID)
            }
        }
    }
}
