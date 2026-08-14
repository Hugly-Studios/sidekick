# Как добавить модуль

```bash
make new-module NAME=Awake
```

Генератор создаёт каталоги, шаблон фичи с двумя `init`, тест, строку в `Project.swift` и регистрацию в `AppEnvironment.featureTypes`.

## Контракт

См. [Features/AGENTS.md](../Features/AGENTS.md). Кратко:

- настройки только через `context.settings`;
- `deactivate()` возвращает систему как было;
- никаких обращений к меню-бару и CLI;
- системные вызовы за протоколами;
- приватный API — с тестом на резолв символов.

## После генератора

1. Заполнить `descriptor` (title, summary, symbol, `requiredPermissions`).
2. Подставить нужные швы (`PowerState`, `Clock`, …) вместо заглушки.
3. Команды должны возвращать `String`.
4. `make generate && make verify`.
5. `make install && scripts/smoke.sh`, затем `sidekick features enable awake --json`.

## Проверка

Модуль появляется в настройках в разделе «Модули». Команды попадают в меню и в `sidekick commands` только после успешного `activate()`.
