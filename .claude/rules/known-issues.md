---
paths:
  - "test/**"
  - "web/**"
  - "analysis_options.yaml"
  - "android/gradle.properties"
  - "lib/main.dart"
  - "lib/core/services/youtube_clients.dart"
  - "lib/features/player/data/audio_handler.dart"
  - "lib/features/player/domain/track_model.dart"
  - "lib/features/player/domain/visualizer_engine.dart"
  - "lib/features/player/presentation/widgets/eq_sheet.dart"
  - "lib/features/importer/data/importer_service.dart"
  - "lib/features/library/presentation/screens/{library_screen,playlists_screen}.dart"
---

# Известные проблемы — не чинить попутно

Всё ниже известно и оставлено осознанно. Чинить только отдельной задачей и по просьбе Orion. Известные проблемы, относящиеся к конкретной теме, лежат в своих файлах: `performance.md`, `data.md`, `lyrics.md`, `release.md`.

## Телеметрия удалена

2026-09-11 по решению Orion (подготовка к Google Play) `TelemetryService` удалён вместе с вызовом в `main()`. Приложение больше ничего не отправляет о пользователе: ни IP, ни данные устройства, ни статистику библиотеки.

Токен Telegram-бота был `const`-строкой в коде и остаётся в публичной истории git (коммит `3957a7e`, его добавил Jules 2026-06-11) и в собранных раньше APK/exe. Бот личный, приложение от него больше не зависит. Отзывать ли токен через @BotFather — решение Orion; на 2026-09-11 он решил не беспокоиться, повторно об этом не напоминать. Переписывать историю git бессмысленно: публичный репозиторий уже могли склонировать.

Не возвращать сбор данных без явного согласия пользователя и политики конфиденциальности; для Google Play это ещё и форма Data safety.

## Запасной путь через Invidious/Piped удалён (2026-09-12)

`InvidiousProxyService` подстраховывал youtube_explode: стрим в `TrackModel.toAudioSource()`, скачивание, метаданные и поиск в `ImporterService`. **Проверено 2026-09-12 с машины Orion: ни один публичный инстанс не отдавал данные** (запрос `/api/v1/videos/<id>`, у Piped — `/streams/<id>`):
- список в коммите: `invidious.io.lol` и `invidious.no-logs.com` отдают HTML вместо JSON, `inv.tux.pizza` — таймаут, `yewtu.be` — 403;
- список из незакоммиченной переделки Orion (2026-06-28): 403, 401, домен не резолвится, ошибка TLS, 404;
- Piped: 403, HTML, два домена не резолвятся;
- `api.invidious.io/instances.json` отвечает, но инстансов с включённым API в нём нет.

Судя по ответам (401/403, мёртвые домены), дело не в сети: публичные инстансы закрыли API. По решению Orion сервис удалён вместе со всеми вызовами. Его незакоммиченная переделка отложена в `git stash` («WIP invidious_proxy_service (28.06)…»), её разбор — в `docs/CHANGELOG_CLAUDE.md`, запись 2026-09-12.

Без запасного пути:
- импорт по ссылке YouTube или Spotify сообщает об ошибке, если ни один клиент youtube_explode не отдал аудио; в плейлисте Яндекс Музыки такой трек пропускается;
- YouTube-трек без локального файла, для которого поток не получен, играет тишину (`assets/mock/silence.mp3`). Бросать исключение из `toAudioSource()` нельзя: `PlayerNotifier.loadPlaylist` ждёт источники всей очереди через `Future.wait`, и одна ошибка сорвала бы загрузку всей очереди.

Коммит Jules `2babf04` (2026-06-28) в описании обещает удалить этот путь целиком, но на деле убрал прокси только из поиска: сервис и фолбэки в импорте и плеере остались. Описаниям коммитов Jules без diff не верить.

Если запасной путь когда-нибудь понадобится — только свой сервер или инстанс, который укажет сам пользователь: публичные закрыты.

## YouTube: скачивание и воспроизведение ломаются на многих видео (с августа 2026)

Проверено 2026-09-12 на машине Orion: лог установленного приложения (stdout через `Start-Process -RedirectStandardOutput`) и пробники на Dart.

- С августа 2026 YouTube требует PO-токен для медиа у клиентов `androidVr` и `ios` (issues youtube_explode_dart #386, #389). На треках Orion (`jYvm-77C7XY`, `AEay6p5LdQg`): `androidVr` — «Sign in to confirm you're not a bot», `ios` — 403 на потоках, `android` — манифест есть, но поток не отдаёт ни байта (issue #379, файл 0 байт), `mweb`, `tv`, `safari` и остальные — «видео недоступно» или «Please sign in». Одинаково на 3.0.5 и 3.1.0.
- Затронуты импорт (`ImporterService._clientFallbackOrder`) и воспроизведение YouTube-треков без локального файла (`TrackModel._tryDirectYouTube`; до обхода ниже там был `getManifest(id)` без списка клиентов, то есть клиент `android`). Подстраховки нет: Invidious/Piped удалены (раздел выше).
- **Проверять только на реальных треках, не на одном популярном видео.** `dQw4w9WgXcQ` качается через `androidVr` до сих пор, и на нём разбор 2026-09-12 сначала пошёл по ложному следу (сеть, VPN, маршруты).
- **Обход с 2026-09-12:** клиент visionOS из неслитых PR #390/#391 объявлен у нас в `lib/core/services/youtube_clients.dart` и стоит первым и в импорте (`kYoutubeClientFallbackOrder`), и в воспроизведении (`TrackModel._getManifest`; если visionOS не ответил — клиент библиотеки по умолчанию). Проверено живым тестом 2026-09-12: оба трека Orion импортируются через `VISIONOS`, воспроизведение YouTube-трека без файла получает прямую ссылку `googlevideo.com`. Это обход того же рода, что и все клиенты библиотеки: YouTube может закрыть и его — тогда в логе будет `[YT] Ошибка (VISIONOS): …`. Раньше пользователей об этом должна сообщить ежедневная проверка на машине Orion (`tool/youtube_health_check.ps1`, `dependencies.md`).
- youtube_explode_dart поднята до 3.1.0: в 3.0.5 `videos.get` (первый шаг импорта) в одном из прогонов вернул «unavailable» на `jYvm-77C7XY`, 3.1.0 на том же видео отработал («Fix: videos apis» в её changelog).
- Надёжного пути нет: yt-dlp сам рекомендует внешний PO Token Provider (BotGuard), JS-движок (deno/QuickJS) решает только n/sig-задачки. Решение Orion (2026-09-12): остаёмся на YouTube — Яндекс Музыка отпадает из-за цензуры и блокировок, у SoundCloud нишевый каталог. Когда закроют visionOS — свой решатель JS-задачек на QuickJS (одна реализация для Android и Windows); PO-токены — только если закроется всё остальное. Обзор альтернатив — `docs/CHANGELOG_CLAUDE.md`, запись 2026-09-12.
- Исправлено 2026-09-12: `_tryDownloadWithClient` качает во временный `*.part`-файл со своим именем, закрывает его до удаления и переименовывает только целиком скачанный. Раньше на Windows файл удалялся при открытом `IOSink` (`PathAccessException`, errno 32), оставались файлы по 0 байт, а два импорта одного трека писали в один файл.

## `flutter analyze` — базовый уровень 7 замечаний

На чистом дереве (2026-09-10) `flutter analyze` выдавал 8 замечаний и 0 ошибок; с 2026-09-12 — 7: вместе с запасным путём Invidious ушло одно `experimental_member_use`. Число записано и в CI (`ANALYZE_BASELINE` в `.github/workflows/ci.yml`): больше — CI падает, исправили старое — уменьшить там же. Это базовый уровень, после своих правок сравнивать с ним: новых не добавлять, старые попутно не чинить. Анализ идёт около 2 минут.

| Уровень | Правило | Файл |
|---|---|---|
| warning | `unused_import` (`dart:math`) | `importer_service.dart` |
| info | `curly_braces_in_flow_control_structures` | `importer_service.dart` |
| warning | `unused_element_parameter` (`size`) | `library_screen.dart` |
| info | `prefer_const_constructors` | `playlists_screen.dart` |
| info | `deprecated_member_use` (`onReorder` → `onReorderItem`) | `playlists_screen.dart` |
| warning ×2 | `experimental_member_use` (`LockCachingAudioSource`) | `track_model.dart` |

Предупреждения `LockCachingAudioSource` ожидаемы: класс в just_audio помечен как experimental, но используется намеренно — для кэширования сетевых источников на мобильных (`<appDocs>/audio_cache`).

## Web не работает

Папка `web/` есть (шаблон Flutter), но на вебе приложение не запустится. `Platform.isWindows` и подобные проверки из `dart:io` вызываются без `kIsWeb` начиная с первых строк `main()`, а на вебе `Platform` бросает `UnsupportedError`. К тому же `sqflite` и работа с файлами на вебе недоступны. Попутно веб не чинить.

## Эквалайзер (подключён 2026-09-12)

До 2026-09-12 эквалайзер к звуку подключён не был: `setEqEnabled` / `setEqBandGain` только меняли состояние, а шторку `eq_sheet.dart` не открывала ни одна кнопка. Теперь:
- `PlayerNotifier` вызывает `AndroidEqualizer.setEnabled` и `band.setGain`, а состояние (`eqEnabled`, `eqBandGains`) берёт у самого эквалайзера;
- полосы платформа отдаёт, только когда у плеера есть источник, поэтому сохранённые настройки применяются после первой загрузки очереди (`_restoreEq`), а шторка ждёт полосы через `loadEq`: 5 секунд, потом «недоступен»;
- настройки хранятся в `equalizer.json` в папке данных (`eq_settings_store.dart`) и применяются, только если число полос совпало;
- кнопка — иконка в верхней панели плеера (`player_main_controls.dart`), только на Android. На других платформах шторка пишет, что эквалайзер есть только на Android: `AndroidEqualizer` из just_audio работает только там.

Известное:
- шторка показывает не больше 5 полос (`bandCount.clamp(0, 5)`); если телефон даёт больше, остальные остаются на своём усилении;
- на настоящем телефоне на 2026-09-12 не проверено: что звук меняется и что настройки переживают перезапуск.

## Визуализатор — мёртвый код, разрешение на микрофон не нужно

`VisualizerEngine` (`visualizer_engine.dart`) задуман как настоящий FFT через `android.media.audiofx.Visualizer`, но не работает ни на одной платформе (проверено 2026-09-11):
- `attachPlayer()` нигде не вызывается. В заголовке файла сказано «из `PlayerNotifier._init()`», но там такого вызова нет, поэтому `stream` не выдаёт ни одного события, и подписчики (`SyllableKaraokeView`) всегда получают `bass = 0`.
- Нативной части нет: каналы `z43.studios.protogenix/control` и `…/events` в `android/` не реализованы.
- `_getSessionId` приводит `player.androidAudioSessionId` к `Stream<int?>`, а в just_audio 0.9.x это `int?` (поток называется `androidAudioSessionIdStream`). Приведение падает, ошибка глотается, и id всегда `null`.

Разрешение `RECORD_AUDIO` в `AndroidManifest.xml` объявлено только ради этого визуализатора и нигде не запрашивается в рантайме. Оживить визуализатор или удалить его вместе с разрешением — решение Orion.

## Предупреждение Flutter про Kotlin Gradle Plugin

При сборке Android Flutter 3.44 пишет, что модуль `app` подключает Kotlin Gradle Plugin (`id("kotlin-android")` в `android/app/build.gradle.kts`) и что в будущих версиях Flutter это приведёт к ошибкам сборки. То же — про плагины, которые подключают KGP сами: `device_info_plus`, `dynamic_color`, `file_picker`, `package_info_plus`, `url_launcher_android`, `wakelock_plus` (список из сборки 2026-09-11). Инструкция по миграции: https://docs.flutter.dev/release/breaking-changes/migrate-to-built-in-kotlin/for-app-developers. Предупреждение было и до правок 2026-09-11. Сейчас сборку не ломает; разбираться при следующем обновлении Flutter, попутно не трогать.

Во время первой release-сборки 2026-09-11 мигратор Flutter сам дописал в `android/gradle.properties` две строки с комментарием «added automatically by Flutter migrator»: `android.builtInKotlin=false` и `android.newDsl=false`. Это флаги AGP 9, а проект на AGP 8.11.1, Kotlin 2.2.20, Gradle 8.14; все сборки 2026-09-11 прошли с этими строками. Закоммитить их вместе с остальным. Откатывать не нужно: при откате мигратор, скорее всего, допишет их при следующей сборке (не проверялось). Убирать — в рамках той же миграции на встроенный Kotlin.

## Visual Studio 2026: что пришлось поправить (2026-09-12)

У Orion Flutter собирает Windows через Visual Studio 2026 Insiders (18.3, см. `flutter doctor -v`; `vswhere` без `-prerelease` предварительные версии не показывает). В CI на `windows-latest` тоже VS 2026, но с более свежим MSVC (14.51) и CMake 4.1. Первый прогон CI упал на двух вещах:
- `permission_handler_windows` собирается с `/await` и `<experimental/coroutine>`, а в MSVC 14.51 это ошибка STL1011. Обход — макрос `_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS` для цели `permission_handler_windows_plugin` в `windows/CMakeLists.txt`. Убрать, когда плагин перейдёт на `<coroutine>` из C++20. У Orion с MSVC из 18.3 это пока предупреждение, но после обновления студии упало бы и локально.
- `audiotags` не распаковывал свой архив через symlink — пакет удалён (`dependencies.md`).

## Тесты

- Реальное покрытие: парсер текстов (`test/features/player/domain/advanced_lrc_parser_test.dart`), перенос баз (`test/core/services/legacy_data_migration_test.dart`) и обновления (`test/features/updater/` — там же пример тестов с локальным `HttpServer` вместо сети).
- `test/widget_test.dart` — smoke-тест с `skip: true`.
- Тесты с файлами — только во временной папке (`Directory.systemTemp.createTemp`), как в тесте переноса.
- **Любой тест, который трогает sqflite, обязан сначала вызвать:**
  ```dart
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  ```
  Без этого на хост-машине нет реализации sqflite. Базы в тестах открывать через `inMemoryDatabasePath` или во временной папке. Синглтоны `LibraryDatabase.instance` / `PlaylistDatabase.instance` берут путь из `AppPaths.databasesDir`, который задаётся только в `main()` (`AppPaths.init()`): без него тест упадёт с `LateInitializationError`, а с ним будет писать в настоящие данные приложения (см. `data.md`).
- Любой тест, который создаёт `playerProvider`, упадёт с `LateInitializationError`: глобальный `audioHandler` инициализируется только в `main()` через `initAudioService()`.
