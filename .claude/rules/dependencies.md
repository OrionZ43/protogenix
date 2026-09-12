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
  - Закрыты явно: `audiotags` (раздел ниже), `just_audio` 0.10+ и `audio_session` 0.2+, `flutter_riverpod` 3+ и неиспользуемая кодогенерация (`riverpod_annotation`, `riverpod_generator`, `build_runner`).
  - Почему явно: первый же PR (2026-09-12) принёс их все разом. Общее правило «без semver-major» Dependabot для pub в группе не применил, а переход 0.9 → 0.10 он считает минорным.
  - Переход на just_audio 0.10 и riverpod 3 — отдельные задачи с переделкой кода.
- `.github/workflows/ci.yml` на каждый PR и на push в master:
  - `flutter analyze` — падает, если замечаний больше базового уровня (`ANALYZE_BASELINE`, сейчас 7, см. `known-issues.md`);
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

## `audiotags` — строго `1.1.3`

Версия зафиксирована точно, без `^`; в `pubspec.yaml` рядом есть комментарий. Версии 1.2+ переходят на native assets и ломают сборку под Windows и Android.

- Не менять версию и не заменять на `^1.1.3`.
- Обычный `flutter pub upgrade` точную версию не трогает. А `flutter pub upgrade --major-versions` переписывает ограничения в `pubspec.yaml`: не запускать его без просмотра diff, а после запуска вернуть `audiotags: 1.1.3`.

**Факт (2026-09-11): пакет не используется.** `audiotags` не импортируется нигде в `lib/` и не импортировался ни разу за всю историю git (`git log -S "package:audiotags" -- lib` пуст). При этом он попадает в сборки (`audiotags.dll` 0,8 МБ в Windows-релизе, регистранты плагинов Windows/Linux/macOS) и тянет `flutter_rust_bridge` 1.82.6. Хак с `namespace` в `android/build.gradle.kts` написан для старых плагинов, и `audiotags` в его комментарии назван примером. Удалить пакет — решение Orion; пока он в `pubspec.yaml`, правило про 1.1.3 действует.

## `youtube_explode_dart` — рабочий клиент YouTube объявлен у нас

С 2026-09-12 версия `^3.1.0` (обновление с 3.0.5 поменяло в `pubspec.lock` только сам пакет). Клиент visionOS, через который сейчас работают скачивание и воспроизведение, объявлен в нашем коде (`lib/core/services/youtube_clients.dart`), а не в библиотеке: на 2026-09-12 он есть только в неслитых PR #390/#391, а релизов библиотеки нет с мая 2026. Почему так и что сломал YouTube — `known-issues.md`, раздел про YouTube.

При обновлении библиотеки:
- прочитать changelog и открытые issues про 403 и «not a bot»;
- если в самой библиотеке появился клиент visionOS или решатель JS-задачек без deno — перейти на них и убрать дубль из `youtube_clients.dart`;
- проверять живым импортом **реальных** треков, а не одного популярного видео: `dQw4w9WgXcQ` проходит даже через сломанные клиенты;
- если автор снова затянет с исправлением, лицензия (BSD) позволяет форк: перенести исправление из PR в свой форк на GitHub и подключить его в `pubspec.yaml` как git-зависимость, сохранив копирайт.

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
