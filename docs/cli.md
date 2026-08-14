# CLI

Бинарник приложения сам является CLI. Обёртка `scripts/sidekick.sh` выбирает `/Applications/Sidekick.app`, затем Release/Debug из `build/`.

Все глаголы принимают `--json`.

| Команда | Кто отвечает |
|---|---|
| `status` | запущенное приложение |
| `features list \| enable \| disable` | запущенное приложение |
| `commands` | запущенное приложение |
| `run <id> [--arg …]` | запущенное приложение |
| `settings get \| set` | запущенное приложение |
| `logs --since <duration> [--level error]` | процесс CLI через `OSLogStore.local()` |
| `doctor` | приложение, если запущено; иначе локальный отчёт без TCC |
| `quit` | запущенное приложение |

Запуск без глагола открывает приложение. Неизвестный глагол — ошибка в stderr и код 1, а не запуск GUI.

Сокет: `~/Library/Application Support/com.hugly.sidekick/cli.sock`. Рядом `cli.pid`, он появляется раньше сокета. Если сокета нет — `notRunning` (код 2). Сокет без pid тоже `notRunning`: файлы не удаляются, потому что это может быть идущий старт. Удаляются только когда pid есть и мёртв — `staleSocket` (код 2).

`doctor --json` — подпись, Team ID, login item, иконка в строке меню, статусы разрешений и `settingsURL`. Геометрию иконки измеряет процесс CLI: у запущенного приложения уже есть свой `NSStatusItem`, и второй мерил бы соседа.

Ворота установки — `status --json`: он требует живой сокет. `doctor` для этого не годится, он отвечает и без приложения.

`scripts/smoke.sh` ставит Release, если `/Applications/Sidekick.app` нет, включает `workspaces`, гоняет `workspaces.list`, затем `doctor` и `logs`. Команды, меняющие глобальное состояние (`workspaces.capture`), только с `--allow-destructive`. Нехватка разрешения модуля — код 3.
