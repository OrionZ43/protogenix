---
paths:
  - "lib/main.dart"
  - "lib/core/services/{app_paths,legacy_data_migration}.dart"
  - "lib/features/library/**"
  - "lib/features/importer/**"
  - "lib/features/search/**"
  - "lib/features/player/presentation/providers/player_provider.dart"
  - "lib/features/player/domain/track_model.dart"
  - "test/core/services/**"
---

# Данные: базы, связь библиотеки и плеера, хранение файлов

## Две отдельные базы sqflite

| Синглтон | Файл | Таблицы | Версия схемы |
|---|---|---|---|
| `LibraryDatabase` | `protogenix.db` | `tracks` | 2 |
| `PlaylistDatabase` | `protogenix_playlists.db` | `playlists`, `playlist_tracks`, `favorites` | 1 |

- `playlist_tracks.trackId` и `favorites.trackId` ссылаются на `tracks.id` **через границу файлов БД**, поэтому внешнего ключа нет и быть не может. Удаление трека (`LibraryNotifier.removeTrackWithFiles`, пачкой — `removeTracksWithFiles`) плейлисты и избранное не трогает: там остаются висячие id.
- Внутри `protogenix_playlists.db` для `playlist_tracks` объявлен `FOREIGN KEY (playlistId) … ON DELETE CASCADE`, но **он не работает**. SQLite применяет внешние ключи только после `PRAGMA foreign_keys = ON`, а в коде этого нет (`onConfigure` не задан). Проверено 2026-09-10: `PRAGMA foreign_keys = 0`, после удаления плейлиста его строки в `playlist_tracks` остаются.
- Код, который читает эти таблицы, молча пропускает отсутствующие треки: `PlaylistTracksNotifier._load` фильтрует через `whereType`, `playlistTracksProvider` — через `if (match.isNotEmpty)`. `favoritesProvider` хранит id как есть, включая удалённые.
- Каскад попутно не «чинить»: включение `PRAGMA foreign_keys` меняет поведение уже существующих баз у пользователей. Это отдельная задача, вместе с чисткой висячих строк.

## Библиотека и плеер не связаны реактивно

`libraryProvider` (`LibraryNotifier`) и `playerProvider` (`PlayerNotifier`) читают `LibraryDatabase` независимо друг от друга. После любого изменения данных библиотеки нужно вызвать **оба**:

```dart
await ref.read(libraryProvider.notifier).reload();
await ref.read(playerProvider.notifier).reloadFromLibrary();
```

Если забыть один вызов, состояние разъедется молча: медиатека и очередь плеера будут показывать разное.

Где это вызывается (на 2026-09-10):
- импорт (`import_manager.dart`, с 2026-09-13 — для ссылок, «В медиатеку» в поиске, своих файлов, перетаскивания и музыки с телефона; один за раз, остальные в очереди): `libraryProvider.reload()` и перечитывание плейлистов по ходу импорта, не чаще раза в 2 секунды, после каждого импорта очереди и в конце; `reloadFromLibrary()` — только если очередь пуста. До этого шторка импорта вызывала оба в конце и сбрасывала очередь на первый трек, а по ходу импорта не обновлялось ничего;
- `track_edit_sheet.dart` — оба;
- удаление: один трек — `track_context_menu.dart`, пачкой — выделение в `library_screen.dart` (с 2026-09-13). `removeTrackWithFiles` / `removeTracksWithFiles` сами обновляют `libraryProvider` (пачка — одним обновлением в конце); `reloadFromLibrary` — только если среди удалённых играющий трек. Пачка ещё перечитывает треки плейлистов. Удаляются запись, аудиофайл (кроме музыки с телефона), текст и обложка; обложка — с 2026-09-13, до этого она оставалась в `covers/`.

**Цена правила.** `reloadFromLibrary()` → `_loadLibrary()` → `loadPlaylist(вся библиотека, initialIndex: 0)`: очередь пересобирается целиком с индекса 0, и текущий трек сменится на первый в библиотеке (самый новый по `addedAt`). То есть это обход, а не дизайн. Правильное решение — чтобы плеер слушал изменения библиотеки и точечно правил очередь, сохраняя текущий трек и позицию. Это отдельная задача, попутно её не делать.

**Новый трек не попадает в играющую очередь**, пока она не пуста: так у всех импортов через `ImportManager`, с 2026-09-13 — и у «В медиатеку» в поиске (раньше он шёл мимо менеджера и перечитывал только медиатеку). Не исправлять это добавлением `reloadFromLibrary()`: такой вызов прервёт музыку при каждом импорте. Правильно — точечно дописывать трек в очередь плеера (то же решение, что в «Цене правила» ниже).

Так же устроен `LibraryNotifier.updateLrcPath` (ручной выбор текста): он обновляет только библиотеку, и у `TrackModel` в очереди `lrcPath` устаревает. На текущую сессию это не влияет, потому что karaoke использует свой кэш (см. `lyrics.md`).

## Версионирование схемы

- `LibraryDatabase`: `version: 2`. `onCreate` создаёт **полную актуальную** схему, а `onUpgrade` содержит пошаговые миграции (`if (oldVersion < 2) ALTER TABLE …`). При изменении схемы нужно поднять `version`, обновить `CREATE TABLE` в `onCreate` **и** добавить шаг `if (oldVersion < N)` в `onUpgrade`. Если сделать только одно из двух, у новых и старых установок окажется разная схема.
- `PlaylistDatabase`: `version: 1`, `onUpgrade` **нет вообще**. Его нужно добавить при первом же изменении схемы.
- Колонка `tracks.audioQuality` (добавлена в v2) не используется: `LibraryTrack.toMap()`/`fromMap()` её не пишут и не читают, и больше она нигде в `lib/` не встречается. Удалять колонку не нужно (`DROP COLUMN` — лишний риск миграции); если понадобится, достаточно добавить поле в модель.

## Где лежат данные

За пути отвечает `AppPaths` (`lib/core/services/app_paths.dart`). `AppPaths.init()` вызывается в `main()` до первого обращения к базам. `LibraryDatabase`, `PlaylistDatabase`, `ImporterService`, `LyricsService.saveLrc` и кэш `TrackModel` берут пути только оттуда — новые места хранения тоже заводить через `AppPaths`.

| Что | Android (и iOS/macOS) | Windows | Linux |
|---|---|---|---|
| Базы (`AppPaths.databasesDir`) | `getDatabasesPath()` — приватная папка приложения | `%LOCALAPPDATA%\Z43 Studios\Protogenix\databases` | `<getApplicationSupportDirectory()>/databases` |
| `music/`, `covers/`, `lyrics/`, `audio_cache/` (от `AppPaths.dataDir`) | `getApplicationDocumentsDirectory()` — приватная папка приложения | `%LOCALAPPDATA%\Z43 Studios\Protogenix` | `getApplicationSupportDirectory()` |

- **Android:** пути не менялись. Удаление приложения стирает всё (см. `release.md` про подпись).
- **Windows:** путь собран явно из переменной `LOCALAPPDATA`, а не через `getApplicationSupportDirectory()`. Тот берёт `%APPDATA%\<CompanyName>\<ProductName>` из `windows/runner/Runner.rc`, и правка метаданных exe молча увела бы данные в пустую папку. Если когда-нибудь переходить на `path_provider`, учитывать это.
- **Linux** не тестировался; путь идёт из `path_provider_linux`.
- Пути в базе (`tracks.filePath`, `coverPath`, `lrcPath`) хранятся **абсолютными**. Если когда-нибудь переносить сами файлы, переписывать и их.
- **Свои файлы** (`ImporterService.importLocalFiles`, с 2026-09-13): id — `local_` и 16 символов SHA-1 от размера и первых 64 КБ файла (`localTrackId`, `importer/data/local_tags.dart`), копия — `music/<id>.<расширение>`, встроенная обложка — `covers/<id>.jpg|png`. Тот же файл второй раз не импортируется («уже были в медиатеке»).
  - До этого id собирался из имени файла, но в нём оставались только латиница и цифры. У файлов с русскими названиями одной длины id совпадал, и второй трек затирал первый (`insertTrack` — `ConflictAlgorithm.replace`), а одноимённые файлы из разных папок перезаписывали копию друг друга. Уже импортированные треки остались со старыми id.
- **Теги старых своих файлов** перечитываются один раз при запуске (`LocalTagsMigration.runOnce` из `main()`, флаг `localTagsReread` в `settings.json`). Только у треков, которые явно не правили руками: исполнитель «Unknown Artist», альбом «Local Import» и название, совпадающее с именем скопированного файла.
- **Музыка с телефона** (Android, `importDeviceTracks`, с 2026-09-13): `source` = `device`, `filePath` — путь к файлу пользователя из MediaStore, файл не копируется. id — тот же хэш содержимого, так что файл, добавленный и вручную, и с телефона, в медиатеку дважды не попадёт. Удаление трека такой файл **не удаляет** — только запись, текст и обложку (их сохраняло приложение); оба диалога удаления это говорят.
- **Треки из Яндекс Музыки** (`_importYandexCollection`): id — id ролика YouTube, `title` — название из Яндекса с версией в скобках, `artist` — все исполнители через «, », `album` — альбом трека, а без него название плейлиста. По этим трём полям повторный импорт узнаёт уже скачанное без поиска на YouTube (`YandexLibraryIndex`, с 2026-09-13). Меняешь, что импорт пишет в эти поля, — меняй и ключ, иначе повторный импорт снова пойдёт искать каждый трек.
- **Настройки интерфейса** — `settings.json` в папке данных (`AppSettingsStore`, `core/services/app_settings_store.dart`): `lyricsLinesOnly`, `discordPresence` (статус в Discord, с 2026-09-14; ключа нет — включён) и служебный флаг `localTagsReread`. Переключаются на экране «Настройки» (`features/settings/`). Эквалайзер хранится отдельно, в `equalizer.json`.

### Перенос со старого места (`LegacyDatabaseMigration`, с 2026-09-11)

До этого на Windows/Linux базы лежали в `<рабочая папка процесса>/.dart_tool/sqflite_common_ffi/databases/` (умолчание `sqflite_common_ffi`): путь зависел от того, откуда запустили приложение. Файлы лежали в `getApplicationDocumentsDirectory()`, на Windows — прямо в корне «Документов» пользователя.

При первом запуске новой версии `LegacyDatabaseMigration`:
- ищет старые базы в `.dart_tool/sqflite_common_ffi/databases` относительно текущей рабочей папки и относительно папки exe и берёт ту, где базы менялись последними;
- **копирует** обе базы вместе со служебными файлами SQLite (`-journal`, `-wal`, `-shm`) через временный файл; старые остаются резервной копией;
- никогда не перезаписывает базу, которая уже есть на новом месте;
- ставит маркер `.legacy_migration_done` в папке баз и больше не запускается;
- если копирование упало, в этой сессии приложение читает старую папку (библиотека не пустая), маркер не ставится, перенос повторится при следующем запуске.

Файлы, скачанные до переноса (музыка, обложки, тексты в «Документах»), **остаются на месте**: пути в базе абсолютные и продолжают работать, а при удалении трека `removeTrackWithFiles` удаляет файлы по этим путям. Новые файлы идут в новую папку. Переносить гигабайты музыки при первом запуске сознательно не стали.

- **В разработке** (`flutter run -d windows`) рабочая папка — корень проекта, поэтому при первом запуске dev-база скопируется из `<проект>/.dart_tool/…` в `%LOCALAPPDATA%\Z43 Studios\Protogenix\databases`. После этого `flutter clean` её уже не сотрёт. Dev-сборка и установленная версия на одной машине пользуются одними и теми же данными.
- Тесты переноса: `test/core/services/legacy_data_migration_test.dart`.
- **Проверено вживую 2026-09-11:** release-exe запущен с рабочей папкой проекта; обе dev-базы (12 288 и 28 672 байт) и маркер появились в `%LOCALAPPDATA%\Z43 Studios\Protogenix\databases`, старые копии остались в `.dart_tool`.
- ⚠ **Ограничение.** Перенос находит старые базы только относительно текущей рабочей папки и папки exe. Установщик ставит программу в новое место (`%LOCALAPPDATA%\Programs\Protogenix`), поэтому у тех, кто пользовался распакованной zip-сборкой, база осталась в `<папка zip>\.dart_tool\sqflite_common_ffi\databases` и сама не найдётся. После первого запуска установленная версия создаст пустые базы, и дальше автоматический перенос их уже не перезапишет. Для таких людей нужен ручной перенос: скопировать обе `.db` из старой папки в `%LOCALAPPDATA%\Z43 Studios\Protogenix\databases` **до** первого запуска установленной версии. Если таких пользователей станет много — делать импорт из старой папки в интерфейсе.

## Модели

`LibraryTrack` (модель БД) превращается в `TrackModel` (модель плеера) через `toTrackModel()`; обложка берётся как `FileImage(coverPath)` или заглушка `kCoverPlaceholder` (`lib/core/theme/cover_placeholder.dart` → `assets/images/cover_placeholder.png`; до 1.0.1 заглушкой была тестовая картинка `mock_cover.jpg`, и у всех своих файлов оказывалась одна чужая обложка). Новое поле трека добавляется:
- в `LibraryTrack`: поле, `copyWith`, `toMap`, `fromMap`;
- в схему (см. выше);
- если оно нужно плееру — в `TrackModel` и `toTrackModel()`.
