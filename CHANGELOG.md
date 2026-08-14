# Changelog

## Unreleased

- Тулчейн на mise: tuist, swiftlint, xcbeautify, lefthook, actionlint.
- `make verify` — единые ворота: формат, безопасность, сборка, тесты.
- Источники модулей через `buildableFolders`; Swift 6.2, approachable concurrency, hardened runtime.
- `Core/ControlSurface` — Unix-сокет CLI ↔ GUI вместо `DistributedNotificationCenter`.
- CLI: `status`, `features`, `commands`, `run`, `settings`, `logs`, `doctor`, `quit` с `--json`.
- `Core/SystemKit`, `Core/PermissionsKit`, `Core/TestSupport`.
- `FeatureRegistry` не активирует модуль без `requiredPermissions`.
- `make new-module`, `make update`, `scripts/smoke.sh`.
- Установка ищет чужие копии по bundle id; `uninstall --purge` чистит support/caches/TCC.
- Версия: маркетинговая из git-тега, build number из `git rev-list --count HEAD`.
- CI на `macos-26` + mise; контракт агента в `AGENTS.md`.
