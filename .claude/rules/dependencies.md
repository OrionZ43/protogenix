---
paths:
  - "pubspec.yaml"
  - "pubspec.lock"
  - "lib/core/services/youtube_clients.dart"
  - "lib/features/library/data/providers/netease_provider.dart"
  - ".github/**"
  - "tool/youtube_health_check.*"
---

# Зависимости: что не трогать

## Автопоиск обновлений: Dependabot и CI (с 2026-09-12)

- `.github/dependabot.yml`: каждый день в 06:00 по Минску Dependabot проверяет pub.dev и открывает PR. `youtube_explode_dart` идёт отдельным PR (группа `youtube`), всё остальное — одним общим (`other`). Раз в неделю — версии GitHub Actions в `ci.yml`.
  - В общий PR идут только минорные версии и патчи.
  - Закрыты явно: `just_audio` 0.10+ и `audio_session` 0.2+, `flutter_riverpod` 3+ и неиспользуемая кодогенерация (`riverpod_annotation`, `riverpod_generator`, `build_runner`).
  - Почему явно: первый же PR (2026-09-12) принёс их все разом. Общее правило «без semver-major» Dependabot для pub в группе не применил, а переход 0.9 → 0.10 он считает минорным.
  - Переход на just_audio 0.10 и riverpod 3 — отдельные задачи с переделкой кода.
- `.github/workflows/ci.yml` на каждый PR и на push в master:
  - `flutter analyze` — падает, если замечаний больше базового уровня (`ANALYZE_BASELINE`, сейчас 6, см. `known-issues.md`);
  - тесты и сборка Windows; готовая сборка лежит в артефактах запуска 7 дней;
  - сборка APK arm64. Секретов нет: APK подписан debug-ключом и годится только как проверка, что проект собирается.
- **Зелёный CI не значит, что скачивание работает:** тесты в сеть не ходят. PR группы `youtube` проверять вживую: скачать артефакт `protogenix-windows-x64`, закрыть установленную версию (второй экземпляр сразу закрывается), запустить `protogenix.exe` из архива и импортировать два-три своих трека, а не одно популярное видео. Данные у этой сборки общие с установленной.
- **Ежедневная проверка на машине Orion** (с 2026-09-12) ловит то, чего не видит Dependabot: YouTube ломает клиентов и без новой версии библиотеки.
  - `tool/youtube_health_check.ps1` запускает `tool/youtube_health_check.dart`: метаданные и первые 256 КБ двух треков Orion через клиентов в порядке импорта, плюс поиск.
  - Задание Планировщика «Protogenix YouTube check» (`-Install` / `-Uninstall`): каждый день в 12:00, пропущенный запуск — при первой возможности, только при сети и когда Orion вошёл в систему.
  - Уведомление Windows — если visionOS не справился, но выручили запасные клиенты (код 1), что-то не качается совсем (2) или проверка не запустилась. Нет сети (3) — только запись в лог `%LOCALAPPDATA%\Z43 Studios\health\youtube.log`.
  - На серверах GitHub её не гоняем: YouTube режет IP дата-центров («not a bot»), были бы ложные тревоги.
  - Проверка повторяет логику скачивания, а не вызывает `ImporterService` (тот тянет Flutter и базы). Поменялся порядок клиентов или способ скачивания в импорте — поправить и её.
- Дальше: слить PR, `git pull` и выпустить релиз одной командой — `tool/release.ps1 -Bump patch -NotesFile docs/release-notes/vX.Y.Z.md -Publish` (`release.md`).
- Версию Flutter в CI (`FLUTTER_VERSION`) Dependabot не обновляет: поднимать вручную вместе со своим Flutter.

## `audiotags` удалён (2026-09-12)

Пакет не импортировался в `lib/` ни разу за всю историю git, но попадал в сборки (`audiotags.dll` 0,8 МБ, регистранты плагинов) и тянул `flutter_rust_bridge`. Версия была прибита к 1.1.3: 1.2+ переходит на native assets и ломала сборку.

С CMake 4 из Visual Studio 2026 сборка под Windows падала и на 1.1.3: архив с библиотекой не распаковывался через `windows/flutter/ephemeral/.plugin_symlinks` («Cannot extract through symlink», CI 2026-09-12). У Orion это не всплывало, потому что архив давно лежал распакованным в кэше пакетов. На чистом кэше упало бы так же.

По решению Orion пакет удалён. Если понадобится чтение тегов — брать пакет без нативной сборки или сначала проверить его на чистом кэше и в CI.

## `audio_metadata_reader` — теги своих файлов (с 2026-09-13)

Чистый Dart, без нативной сборки: после истории с `audiotags` (раздел выше) пакеты с Rust или своей сборкой под платформу не берём.
- Читает MP3 (ID3v1/v2), M4A/MP4, FLAC, OGG/Opus, WAV и встроенную обложку.
- API синхронный, поэтому вызывается через `Isolate.run` (`importer/data/local_tags.dart`).
- Подтянул `charset` и `intl`.
- Умеет и записывать теги — пригодится, если редактирование трека будет менять сам файл.

## `desktop_drop` — перетаскивание файлов в окно (с 2026-09-13)

0.8.4, издатель mixin.dev. На Windows — один C++ файл (`cmake_minimum_required(3.15)`), без Rust и внешних библиотек. На Android плагин только вешает `OnDragListener`, разрешений не добавляет; AGP 8 поддерживается с 0.8.2 при Kotlin Gradle Plugin 2.x (у нас 2.2.20). `super_drag_and_drop` не брать: Rust через cargokit, без Rust он качает готовые бинарники прямо во время сборки.

## `youtube_explode_dart` — рабочий клиент YouTube объявлен у нас

С 2026-09-12 версия `^3.1.0` (обновление с 3.0.5 поменяло в `pubspec.lock` только сам пакет). Клиент visionOS, через который сейчас работают скачивание и воспроизведение, объявлен в нашем коде (`lib/core/services/youtube_clients.dart`), а не в библиотеке: на 2026-09-12 он есть только в неслитых PR #390/#391, а релизов библиотеки нет с мая 2026. Почему так и что сломал YouTube — `known-issues.md`, раздел про YouTube.

При обновлении библиотеки:
- прочитать changelog и открытые issues про 403 и «not a bot»;
- если в самой библиотеке появился клиент visionOS или решатель JS-задачек без deno — перейти на них и убрать дубль из `youtube_clients.dart`;
- проверять живым импортом **реальных** треков, а не одного популярного видео: `dQw4w9WgXcQ` проходит даже через сломанные клиенты;
- если автор снова затянет с исправлением, лицензия (BSD) позволяет форк: перенести исправление из PR в свой форк на GitHub и подключить его в `pubspec.yaml` как git-зависимость, сохранив копирайт.
- **С 2026-09-13 так и сделано.** Поиск падал, если в выдаче прямая трансляция (`known-issues.md`).
  - Форк: `github.com/OrionZ43/youtube_explode_dart`, ветка `fix/search-dynamic-runs`, коммит `4dee1fc` — ровно v3.1.0 (у автора master = тег v3.1.0) плюс исправление в `search_page.dart`.
  - В `pubspec.yaml` — git-зависимость по коммиту. PR автору — на решение Orion.
  - Вернуться на pub.dev, когда исправление выйдет в релизе автора. Dependabot git-зависимость не обновляет; ежедневная проверка YouTube (выше) продолжает работать.
  - Баннер «Terms of use» с политическими заявлениями есть в README C#-оригинала YoutubeExplode (Tyrrrz), а не в Dart-порте: у порта лицензия BSD, в README ничего подобного нет (проверено в клоне).

## `media_kit` нужен только на Windows/Linux

На Android, iOS и macOS `just_audio` играет сам (ExoPlayer / AVPlayer); `JustAudioMediaKit.ensureInitialized()` в `main.dart` вызывается только на Windows и Linux. Сейчас в `pubspec.yaml` стоят `media_kit`, `media_kit_video` и `media_kit_libs_video`:
- `media_kit_video` в коде не импортируется;
- `media_kit_libs_video` — видео-вариант. На Android он кладёт в APK `libmpv.so` (11,8 МБ на arm64), на Windows — `libmpv-2.dll` 28,4 МБ плюс ~17,7 МБ ANGLE/SwiftShader.

README `just_audio_media_kit` для аудио советует `media_kit_libs_windows_audio` и `media_kit_libs_linux`. Замена — отдельная задача: после неё проверить воспроизведение на Windows и Linux и выравнивание `.so` под 16 КБ (`release.md`).

## Перехватчик `X-Real-IP` в `netease_provider.dart` — не удалять

Interceptor в конструкторе `NetEaseProvider` на каждый запрос ставит `X-Real-IP` и `X-Forwarded-For` со случайным адресом из `211.161.244.0/24`. Это намеренный обход гео-блокировки NetEase: без него API не отвечает за пределами Китая. К тому же обходу относятся заголовки Linux-клиента (`User-Agent`, `Cookie`) — они нужны, чтобы не получать ошибку `-460`.

Это не уязвимость приложения. Sentinel уже принимал подмену IP за уязвимость (ветка `security-fix-ip-spoofing-…`, апрель 2026), после чего в `.jules/bolt.md` появилось правило «никогда не удалять этот Interceptor».

## Кодогенерации нет

`riverpod_generator` и `build_runner` лежат в `dev_dependencies`, но не используются. Все провайдеры написаны руками (`StateNotifierProvider`, `AsyncNotifierProvider`, `FutureProvider.family`, `StateProvider`); директив `part '….g.dart'` и самих `.g.dart`-файлов нет.

- Не запускать `build_runner`.
- Новые провайдеры тоже писать руками, без `@riverpod`, иначе в проект притянется генерация, которой в нём нет.
