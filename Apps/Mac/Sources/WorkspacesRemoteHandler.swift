import AppCore
import Workspaces

/// Performs remote requests against the live Workspaces feature.
@MainActor
enum WorkspacesRemoteHandler {
    static func install(features: FeatureRegistry) {
        RemoteControl.observe { action, argument in
            guard let feature = features.feature(WorkspacesFeature.self) else {
                return "модуль «Рабочие столы» выключен"
            }

            switch action {
            case .status:
                return argument == "verbose"
                    ? status(of: feature) + "\n"
                        + feature.windowDiagnostics().joined(separator: "\n")
                    : status(of: feature)
            case .list: return list(of: feature)
            case .capture: return await capture(feature, name: argument)
            case .restore: return await restore(feature, name: argument)
            }
        }
    }

    private static func status(of feature: WorkspacesFeature) -> String {
        feature.reload()

        return """
            доступ к окнам: \(feature.hasWindowAccess ? "есть" : "нет")
            снимков: \(feature.snapshots.count)
            \(feature.visibleWindowSummary())
            автоперестановка столов: \
            \(feature.orderGuard.isAutoRearrangeDisabled ? "выключена" : "включена")
            порядок столов: \(feature.spaceOrderDrifted() ? "отличается от снимка" : "как в снимке")
            """
    }

    private static func list(of feature: WorkspacesFeature) -> String {
        feature.reload()

        guard !feature.snapshots.isEmpty else { return "снимков нет" }

        return feature.snapshots
            .map { snapshot in
                let marker = feature.defaultSnapshotID == snapshot.id ? "*" : " "
                return
                    "\(marker) \(snapshot.name) — \(snapshot.spaceCount) столов, \(snapshot.windowCount) окон"
            }
            .joined(separator: "\n")
    }

    private static func capture(_ feature: WorkspacesFeature, name: String) async -> String {
        await feature.capture(named: name.isEmpty ? nil : name)
        feature.reload()

        if let problems = feature.lastReport?.problems, !problems.isEmpty {
            return problems.joined(separator: "\n")
        }

        guard let snapshot = feature.snapshots.first else { return "снимок не сохранён" }

        return
            "сохранено «\(snapshot.name)»: \(snapshot.spaceCount) столов, \(snapshot.windowCount) окон"
    }

    private static func restore(_ feature: WorkspacesFeature, name: String) async -> String {
        feature.reload()

        let snapshot =
            name.isEmpty
            ? feature.defaultSnapshot
            : feature.snapshots.first { $0.name == name }

        guard let snapshot else { return "снимок не найден" }

        await feature.restore(id: snapshot.id)

        guard let report = feature.lastReport else { return "нет результата" }

        return ([report.summary] + report.problems.map { "проблема: \($0)" })
            .joined(separator: "\n")
    }
}
