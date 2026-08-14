# Релиз

Сейчас релиз — это git-тег `vX.Y.Z`. `scripts/version.sh` пишет:

- `MARKETING_VERSION` из последнего тега;
- `CURRENT_PROJECT_VERSION` из `git rev-list --count HEAD` (монотонно, это то, что сравнивает Sparkle).

`.github/workflows/release.yml` собирает Release и прикладывает zip к GitHub Release.

Локально: `make install` / `make update`.

## Что осталось до Sparkle

Этого ещё нет — отдельный PR, когда появится платный Developer ID:

1. Сертификат Developer ID Application и нотаризация.
2. SPM-зависимость Sparkle.
3. `SUFeedURL` и `SUPublicEDKey` в Info.plist.
4. `generate_appcast` на артефактах.
5. Hardened runtime уже включён; sandbox должен остаться выключенным (`dlsym` с ним несовместим).

Не включать Sparkle «наполовину»: без Developer ID подпись и канал обновлений бесполезны.
