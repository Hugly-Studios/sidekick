# Архитектура

## Принцип

Фича объявляет возможности, оболочка их отображает. Модуль не знает про меню-бар, горячие клавиши, CLI и Shortcuts — он объявляет команды и панель настроек, а поверхности строятся над реестрами автоматически.

```
Surfaces:   Menu bar   Hotkeys   Settings   CLI (sidekick)
                 \        |         /          /
Kernel:      CommandRegistry   FeatureRegistry   EventBus   SettingsStore
                              |
Seams:       SystemKit   PermissionsKit   ControlSurface   TestSupport
                              |
Features:    Workspaces   Awake   Dictation   Messages   ...
```

## Модули репозитория

- `Core/AppCore` — контракт `Feature`, реестры, шина событий, настройки, словарь `PermissionKind`.
- `Core/ControlSurface` — Codable-протокол, Unix-сокет CLI ↔ GUI, `LogReader` через `OSLogStore`.
- `Core/SystemKit` — `Clock`, `WorkspaceObserving`, `PowerState`, `UserNotifying`, `Pasteboarding`, `FileWatching`.
- `Core/PermissionsKit` — живая проверка и запрос TCC, deep-link в System Settings.
- `Core/TestSupport` — фейки, линкуются только тестами.
- `Core/PrivateAPI` / `Automation` / `HotkeysKit` — системные швы Workspaces и оболочки.
- `Apps/Mac` — menu-bar приложение и CLI.
- `Features/<Name>` — один пользовательский модуль.

Каждый модуль описывается фабриками из `Tuist/ProjectDescriptionHelpers/Module.swift`. Источники — `buildableFolders`: `tuist generate` нужен при добавлении модуля, не файла.

Конкурентность: `SWIFT_APPROACHABLE_CONCURRENCY` везде; `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` у приложения и фич; библиотеки `nonisolated`. `ENABLE_HARDENED_RUNTIME = YES`, sandbox выключен.

## Ядро

**`Feature`** — статический `descriptor`, `activate()` / `deactivate()`, `commands`, представления. Системное приходит через `FeatureContext`.

**`FeatureRegistry`** — владеет экземплярами, включённостью и жизненным циклом. Перед `activate()` проверяет `requiredPermissions` через `PermissionChecking`. Отказ — `FeatureActivationError.missingPermission`, команды не регистрируются.

**`CommandRegistry`** — команды активных фич. `run` возвращает `String` для CLI; меню вызывает `runDetached`.

**`EventBus`** — типизированный broadcast между фичами без прямых зависимостей.

**`SettingsStore`** — типизированные ключи. CLI ходит через `inspect` / `write`.

## Control Surface

Протокол `ControlRequest` / `ControlResponse` общий. Транспорт сейчас один: Unix-сокет `~/Library/Application Support/com.hugly.sidekick/cli.sock` (каталог `0700`, сокет `0600`). Клиент проверяется `getpeereid()` и `LOCAL_PEERTOKEN` → `SecCodeCheckValidity` по Team ID. Рядом pid-файл, чтобы отличить «не запущено» от «сокет от упавшего процесса».

XPC зарезервирован для GUI ↔ root-демон (Awake). Между двумя приложениями Mach-сервис не работает вне Xcode.

`DistributedNotificationCenter` больше не используется.

## Разрешения

`PermissionKind` живёт в `AppCore`. `LivePermissionChecker` реализует статус, запрос и `settingsURL`. `sidekick doctor --json` показывает картину целиком.

## Внедрение зависимостей

```swift
public convenience init(context: FeatureContext) {
    self.init(context: context, clock: SystemClock())
}

init(context: FeatureContext, clock: some Clock) { … }
```

`WorkspacesFeature` — эталон: spaces / navigator / inspector / store передаются в designated init.

## Жизненный цикл

`AppDelegate` поднимает `ControlServer`, активирует включённые фичи, при выходе вызывает `deactivate()` и гасит сокет.
