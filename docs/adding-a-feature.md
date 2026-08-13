# Как добавить модуль

Пример: модуль `Awake`.

## 1. Таргет

В `Project.swift` добавьте модуль в список таргетов:

```swift
targets: [
    // ...
]
    + Module.core("AppCore")
    + Module.feature("Awake"),
```

Файлы кладутся в `Features/Awake/Sources/**`, тесты — в `Features/Awake/Tests/**`. Зависимость от `AppCore` фабрика добавляет сама.

## 2. Реализация

```swift
import AppCore
import SwiftUI

@MainActor
public final class AwakeFeature: Feature {
    public static let descriptor = FeatureDescriptor(
        id: "awake",
        title: "Без сна",
        summary: "Не давать ноутбуку засыпать, в том числе с закрытой крышкой",
        symbolName: "moon.zzz",
        requiredPermissions: [],
        isEnabledByDefault: false
    )

    private static let timeoutKey = SettingKey("timeoutMinutes", default: 60)

    private let context: FeatureContext

    public init(context: FeatureContext) {
        self.context = context
    }

    public func activate() async throws {
        // Подготовка ресурсов. Бросьте FeatureActivationError, если чего-то не хватает —
        // причина попадёт в настройки, приложение не сломается.
    }

    public func deactivate() async {
        // Обязательно вернуть систему в исходное состояние.
    }

    public var commands: [Command] {
        [
            Command(id: "awake.toggle", title: "Включить на час", symbolName: "moon.zzz") {
                // действие
            }
        ]
    }

    public func makeSettingsView() -> AnyView {
        AnyView(AwakeSettingsView(context: context))
    }
}
```

Требования к содержимому:

- Настройки читайте только через `context.settings` — он уже изолирован префиксом `features.awake`.
- Меню использует нативный стиль `.menu`, поэтому `makeMenuView()` должен возвращать menu-совместимое содержимое: `Button`, `Toggle`, `Text`, `Divider`.
- Никаких обращений к меню-бару, горячим клавишам или CLI: объявляйте команды, остальное сделает оболочка.

## 3. Регистрация

Единственное место подключения — `AppEnvironment.featureTypes` в `Apps/Mac/Sources/AppEnvironment.swift`:

```swift
static var featureTypes: [any Feature.Type] {
    [AwakeFeature.self]
}
```

## 4. Проверка

```bash
tuist generate
xcodebuild -workspace Sidekick.xcworkspace -scheme Sidekick \
  -configuration Debug -destination 'platform=macOS' test
```

Модуль появится в настройках в разделе «Модули» с переключателем, а его команды — в меню-баре после включения.
