# Sidekick

Расширяемая menu-bar платформа продуктивности для macOS 26. Одно приложение, в которое модулями добавляются повседневные улучшения работы с ноутбуком.

Ядро уже готово, модули добавляются по одному:

- **Workspaces** — снапшот всех рабочих столов, открытых приложений и позиций окон с восстановлением после перезагрузки, плюс фиксация порядка рабочих столов.
- **Awake** — запрет сна, в том числе с закрытой крышкой, таймерные сессии и предохранители по заряду и температуре.
- **Dictation** — надиктовка текста по горячей клавише через on-device распознавание macOS 26.
- **Messages** — перехват кодов из SMS, пришедших на Mac через Continuity, и копирование их в буфер обмена.

## Требования

- macOS 26 или новее
- Xcode 26.6
- [Tuist](https://tuist.dev) — проект описан кодом, `.xcodeproj` не хранится в репозитории

## Сборка

```bash
# Tuist версии из .tuist-version (тот же путь, что использует CI)
TUIST=$(scripts/install-tuist.sh)
"$TUIST" generate

# или, если Tuist уже стоит через brew install --cask tuist
tuist generate
```

Дальше обычная работа в Xcode либо из терминала:

```bash
xcodebuild -workspace Sidekick.xcworkspace -scheme Sidekick \
  -configuration Debug -destination 'platform=macOS' test
```

## Подпись при разработке

По умолчанию проект подписывается ad-hoc, чтобы собираться на любой машине. Ad-hoc подпись меняется при каждой сборке, а macOS привязывает к ней выданные разрешения (Универсальный доступ, Полный доступ к диску) — и сбрасывает их. Чтобы разрешения не приходилось выдавать заново:

```bash
cp Config/Signing.local.xcconfig.example Config/Signing.local.xcconfig
# впишите свой DEVELOPMENT_TEAM, файл в .gitignore
```

## Форматирование

```bash
xcrun swift-format format --in-place --recursive --parallel Apps Core Tuist Project.swift Tuist.swift
```

## Архитектура

Фича объявляет команды, оболочка их отображает: модуль не знает про меню-бар, горячие клавиши и будущий CLI. Подробнее — [docs/architecture.md](docs/architecture.md), как добавить свой модуль — [docs/adding-a-feature.md](docs/adding-a-feature.md).

## Лицензия

MIT, см. [LICENSE](LICENSE).
