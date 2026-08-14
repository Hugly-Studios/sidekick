# Sidekick

Menu-bar платформа продуктивности для macOS 26. Одно приложение, в которое модулями добавляются повседневные улучшения работы с ноутбуком. Фича объявляет команды, оболочка их отображает.

## Структура

- `Apps/Mac` — menu-bar приложение (`LSUIElement`) и CLI `sidekick`
- `Core/AppCore` — `Feature`, реестры, шина событий, настройки
- `Core/ControlSurface` — Unix-сокет CLI ↔ GUI
- `Core/SystemKit` — часы, питание, воркспейс, буфер, уведомления, вотчеры
- `Core/PermissionsKit` — статусы и запрос TCC
- `Core/TestSupport` — фейки только для тестов
- `Features/<Name>` — один пользовательский модуль

Проект генерирует Tuist. `tuist generate` нужен только после добавления **модуля**, не файла: источники — `buildableFolders`.

## Команды

```
make setup      # mise, подпись, зависимости, проект
make verify     # единственные ворота перед PR
make install    # Release в /Applications/Sidekick.app
make update     # git pull --ff-only + install + smoke
make smoke      # сквозная проверка установленного приложения
make new-module NAME=Awake
```

CLI (все глаголы принимают `--json`):

```
sidekick status
sidekick features list | enable <id> | disable <id>
sidekick commands
sidekick run <command.id> [--arg …]
sidekick settings get|set <key> [value]
sidekick logs --since 1h [--level error]
sidekick doctor
sidekick quit
```

Обёртка: `scripts/sidekick.sh` (предпочитает `/Applications/Sidekick.app`).

## Проверка

Агент убеждается, что изменение работает, так:

1. `make verify` — формат, SwiftLint (безопасность), сборка, тесты.
2. Если затронуты установка, сокет, CLI или жизненный цикл приложения: `make install` и `scripts/smoke.sh`.
3. Точечная проверка через `sidekick … --json`. Ненулевой код — провал.
4. Ошибки активации и разрешения смотреть в `sidekick doctor --json`, не угадывать.
5. Логи: `sidekick logs --json --since 10m --level error`.

Команды, которые меняют глобальное состояние системы (запрет сна, перестановка окон, закрытие чужих приложений), на рабочей машине без спроса не гонять. Для них `scripts/smoke.sh --allow-destructive`.

## Границы автономности

Агент **не может** выдать TCC-разрешение. Accessibility, Full Disk Access, микрофон и распознавание речи требуют клика в System Settings. Смягчается так: стабильная подпись сохраняет гранты между переустановками; `doctor --json` называет недостающее разрешение и панель; smoke при нехватке разрешения выходит с кодом 3.

Агент **не может** проверить внешний вид иконки в строке меню. `doctor` измеряет геометрию и отвечает «видна / за вырезом».

Не обещать полную автономность. Если проверка упёрлась в разрешение или визуал — сказать это прямо.

## Контракт модуля

См. [Features/AGENTS.md](Features/AGENTS.md). Новый модуль — `make new-module NAME=…`, не руками.

## Версия и подпись

`scripts/version.sh` пишет `Config/Version.xcconfig`: маркетинговая версия из git-тега, `CURRENT_PROJECT_VERSION` из `git rev-list --count HEAD`. Sparkle сравнивает именно build number.

Подпись: `Config/Signing.local.xcconfig` (gitignored). Ad-hoc в CI. Смена Team ID сбрасывает TCC.

## Чего не делать

- Не регенерировать проект после каждого нового `.swift` файла.
- Не ходить в меню-бар и CLI из модуля.
- Не логировать тела сообщений и содержимое буфера.
- Не ставить Periphery воротами CI (`make dead-code` — вручную).
- Не заводить XCUITest в CI: menu-bar приложение на headless-раннере падает до старта тестов.
