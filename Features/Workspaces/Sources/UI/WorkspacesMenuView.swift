import SwiftUI

/// Status shown in the menu bar dropdown. The feature's commands are rendered by
/// the shell, so this only adds context.
struct WorkspacesMenuView: View {
    let feature: WorkspacesFeature

    var body: some View {
        if !feature.hasWindowAccess {
            Text("Нет доступа к окнам — откройте настройки модуля")
        }

        if let snapshot = feature.defaultSnapshot {
            Text("Снимок «\(snapshot.name)»: \(snapshot.spaceCount) столов, \(snapshot.windowCount) окон")
        } else {
            Text("Снимков пока нет")
        }

        if feature.isBusy {
            Text("Идёт восстановление…")
        }

        if feature.spaceOrderDrifted() {
            Text("Порядок столов отличается от снимка")
        }
    }
}
