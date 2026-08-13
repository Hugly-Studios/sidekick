import Automation
import SwiftUI

struct WorkspacesSettingsView: View {
    let feature: WorkspacesFeature

    @State private var newSnapshotName = ""

    var body: some View {
        Form {
            if !feature.hasWindowAccess {
                permissionSection
            }

            captureSection
            snapshotsSection
            restoreSection
            orderSection

            if let report = feature.lastReport {
                reportSection(report)
            }
        }
        .formStyle(.grouped)
        .onAppear { feature.reload() }
    }

    private var permissionSection: some View {
        Section {
            Label("Нужен доступ к управлению компьютером", systemImage: "lock")
                .foregroundStyle(Color.orange)

            Button("Открыть настройки доступа") {
                AccessibilityAuthorization.prompt()
                AccessibilityAuthorization.openSystemSettings()
            }
        } footer: {
            Text(
                "Без этого доступа нельзя ни прочитать положение окон, ни расставить их. После выдачи доступа выключите и снова включите модуль в разделе «Модули»."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }

    private var captureSection: some View {
        Section("Новый снимок") {
            HStack {
                TextField("Название", text: $newSnapshotName, prompt: Text("Например: работа"))

                Button("Сохранить состояние") {
                    let name = newSnapshotName.trimmingCharacters(in: .whitespaces)
                    newSnapshotName = ""
                    Task { await feature.capture(named: name.isEmpty ? nil : name) }
                }
                .disabled(feature.isBusy)
            }
        }
    }

    private var snapshotsSection: some View {
        Section("Снимки") {
            if feature.snapshots.isEmpty {
                Text("Пока ничего не сохранено")
                    .foregroundStyle(.secondary)
            }

            ForEach(feature.snapshots) { snapshot in
                HStack {
                    VStack(alignment: .leading) {
                        Text(snapshot.name)
                        Text(
                            "\(snapshot.spaceCount) столов, \(snapshot.windowCount) окон · \(snapshot.createdAt.formatted(date: .abbreviated, time: .shortened))"
                        )
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if feature.defaultSnapshotID == snapshot.id {
                        Text("по умолчанию")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }

                    Button("Восстановить") {
                        Task { await feature.restore(id: snapshot.id) }
                    }
                    .disabled(feature.isBusy)

                    Menu {
                        Button("Сделать снимком по умолчанию") {
                            feature.setDefaultSnapshot(id: snapshot.id)
                        }
                        Button("Удалить", role: .destructive) {
                            feature.delete(id: snapshot.id)
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
            }
        }
    }

    private var restoreSection: some View {
        Section("Восстановление") {
            Picker(
                "Режим",
                selection: Binding(
                    get: { feature.mode },
                    set: { feature.setMode($0) }
                )
            ) {
                ForEach(RestoreMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }

            Toggle(
                "Восстанавливать при входе в систему",
                isOn: Binding(
                    get: { feature.restoreOnLogin },
                    set: { feature.setRestoreOnLogin($0) }
                )
            )

            Text(
                "Приложение должно быть добавлено в элементы входа — включите «Запускать при входе в систему» в разделе «Общие». Восстановление начинается через 15 секунд после входа, когда система закончит открывать свои окна."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }

    private var orderSection: some View {
        Section("Порядок рабочих столов") {
            Toggle(
                "Не давать macOS менять порядок столов",
                isOn: Binding(
                    get: { feature.locksSpaceOrder },
                    set: { feature.setLocksSpaceOrder($0) }
                )
            )

            LabeledContent("Автоперестановка") {
                Text(feature.orderGuard.isAutoRearrangeDisabled ? "выключена" : "включена")
                    .foregroundStyle(
                        feature.orderGuard.isAutoRearrangeDisabled ? Color.secondary : Color.orange)
            }

            if feature.spaceOrderDrifted() {
                Label(
                    "Порядок столов отличается от снимка. Порядок нельзя восстановить программно — перетащите столы в Mission Control.",
                    systemImage: "exclamationmark.triangle"
                )
                .foregroundStyle(.orange)
            }

            Text(
                "macOS по умолчанию сама переставляет столы по частоте использования — именно это ломает сохранённый порядок. Настройка живёт в параметрах Dock, поэтому при её изменении Dock перезапускается."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }

    private func reportSection(_ report: RestoreReport) -> some View {
        Section("Последнее восстановление") {
            LabeledContent("Итог", value: report.summary)

            ForEach(Array(report.problems.enumerated()), id: \.offset) { _, problem in
                Label(problem, systemImage: "exclamationmark.circle")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
        }
    }
}
