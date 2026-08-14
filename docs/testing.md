# Тестирование

## Что гоняем

- Swift Testing в юнит-таргетах: `AppCore`, `PrivateAPI`, `SystemKit`, `PermissionsKit`, `ControlSurface`, `Workspaces`, `Sounds`.
- `make verify` — формат, SwiftLint (только безопасность), сборка, тесты. Единственные ворота PR.
- `scripts/smoke.sh` — установленное приложение отвечает на CLI.

## Чего нет в CI

XCUITest для menu-bar приложения (`LSUIElement`) на headless `macos-26` падает до старта тестов: нет интерактивной строки меню. Визуал проверяет человек; `doctor` измеряет геометрию иконки.

Periphery даёт ложные срабатывания на `@Environment` / `@State` (issue #1121). Это `make dead-code`, не CI-ворота.

## Как писать тесты модуля

`Core/TestSupport` линкуется только тестами:

- `FakeClock`, `InMemorySettingsStore`, `FakePermissions`, `RecordingEventBus`
- `TestFeatureContext.make()`

Живые TCC / IOKit / Accessibility в юнит-тесте не трогать.

ControlSurface: кодек и роутер — юнит; сокет — временный путь в одном процессе, без launchd и подписи.

Приватный API: тест, который падает, если символ пропал. Образец — `SkyLightAvailabilityTests`.
