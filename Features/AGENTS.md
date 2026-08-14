# Контракт модуля

Модуль объявляет возможности. Оболочка решает, как их показать. Модуль не знает про меню-бар, горячие клавиши и CLI.

## Обязательно

- Настройки только через `context.settings`. Он уже с префиксом `features.<id>`.
- `deactivate()` возвращает систему в исходное состояние. Не рассчитывать, что процесс всегда завершится корректно — для опасных эффектов нужна своя страховка.
- Никаких обращений к меню-бару, `NSStatusItem`, CLI или `DistributedNotificationCenter`.
- Системные вызовы за протоколами `SystemKit` / `PermissionsKit`, не напрямую к IOKit, `NSWorkspace`, `NSPasteboard`.
- Два инициализатора:

```swift
public convenience init(context: FeatureContext) {
    self.init(context: context, clock: SystemClock())
}

init(context: FeatureContext, clock: some Clock) { … }
```

- Команды возвращают `String` — это то, что видит `sidekick run`.
- Требуемые разрешения перечислить в `descriptor.requiredPermissions`. Реестр не активирует модуль без них.
- Приватный API сопровождается тестом, который падает, если символ перестал резолвиться. Образец: `SkyLightAvailabilityTests`.

## Запрещено

- Создавать живые системные зависимости внутри `init(context:)` без шва для теста.
- Логировать тела сообщений, содержимое буфера обмена, пути к чужим файлам сверх необходимого.
- Менять глобальное состояние в юнит-тесте на машине разработчика.

## Проверка модуля

```
make verify
make install
scripts/smoke.sh
sidekick features enable <id> --json
sidekick run <command.id> --json
sidekick doctor --json
sidekick logs --json --since 10m --level error
```
