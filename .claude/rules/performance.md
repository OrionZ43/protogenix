---
paths:
  - "lib/app/**"
  - "lib/core/widgets/**"
  - "lib/features/**/presentation/**"
---

# Производительность UI

Правила взяты из `.jules/bolt.md` и специфичны для этого приложения: пока играет музыка, плеер обновляет состояние непрерывно.

## Правила для нового кода

1. **`ref.watch(playerProvider.select(...))` — обязательно.** `PlayerNotifier` делает `state = state.copyWith(position: …)` на каждое событие `positionStream` (just_audio шлёт позицию несколько раз в секунду) и ещё на каждое событие `bufferedPositionStream`. `ref.watch(playerProvider)` без `select` перестраивает виджет всё время, пока идёт воспроизведение. Образец — `app_shell.dart`: `playerProvider.select((s) => s.currentTrack != null)`.

2. **Не блокировать UI O(N)-работой в обработчиках и провайдерах.** Сначала дать отрисоваться состоянию загрузки, потом работать:
   - `await SchedulerBinding.instance.endOfFrame;` — дождаться, пока кадр (например, с индикатором загрузки) будет отрисован;
   - по-настоящему тяжёлое (парсинг, сортировка больших списков) — `await Isolate.run(...)`.

   ⚠ В `.jules/bolt.md` для этого предписан `await Future.microtask(() {})`, и он есть в коде (`PlayerNotifier.loadPlaylist`). **Кадр он не отпускает:** микротаски выполняются раньше следующего события event loop, в том числе раньше отрисовки. Проверено 2026-09-10 скриптом: с `Future.microtask` работа выполнилась раньше события, с `Future.delayed(Duration.zero)` — после. В новом коде этот приём не копировать, существующее место попутно не переписывать.

3. **CustomPaint-анимации — через `ValueNotifier` + `ValueListenableBuilder`** (или `ListenableBuilder`) вокруг `CustomPaint`, а не через `setState` в `Ticker`. Иначе на 60–120 FPS перестраивается всё поддерево вместе с жестами и текстом. Образец — `LiveWaveformProgressBar` (`waveform_progress_bar.dart`).

4. **`RepaintBoundary` вокруг часто перерисовываемых элементов списка:** тогда перерисовка одного элемента не тянет за собой весь список. Образец — строки `BeautifulLyricsView` при смене активной строки караоке.

5. **`BackdropFilter` — не внутри скроллящегося контента:** блюр пересчитывается на каждом кадре прокрутки. На статичных панелях (нижняя навигация, шторки) — допустимо.

## Известные нарушения — не чинить попутно

Состояние на 2026-09-10. Исправлять только отдельной задачей.

- **13 мест `ref.watch(playerProvider)` без `select`:** `home_screen.dart`, `library_screen.dart`, `favorites_screen.dart`, `playlists_screen.dart`, `player_screen.dart`, `expanded_player_screen.dart`, `desktop_bottom_player.dart`, `mini_player.dart`, `player_controls_compact.dart`, `queue_panel.dart`, `eq_sheet.dart`, `sleep_timer_sheet.dart`, `music_visualizer_controls.dart`. Особенно дорого это на вкладках (`home`, `library`): они живут в `IndexedStack` и перестраиваются, даже когда не видны.
- **Парсинг в Isolate не реализован**, хотя `.jules/bolt.md` его требует: `KaraokeNotifier` вызывает `AdvancedLrcParser.parse` на UI-изоляте, а `compute`/`Isolate` в `lib/` нигде не используются.
- **`playlistTracksProvider`** (`playlist_provider.dart`) вызывает `LibraryDatabase.getAllTracks()` внутри цикла по трекам плейлиста. Это полное чтение таблицы на каждый трек, O(N×M). Его вызывает каждая `PlaylistCard` в сетке плейлистов (`playlists_screen.dart`). Рядом `PlaylistTracksNotifier._load` делает то же правильно: одно чтение и `Map` по id.

Дополнено 2026-09-11 (аудит перед релизом):

- **Анимированный фон + стекло — главная нагрузка на GPU.** `AnimatedBackground` (через `ProtogenixBackground`) стоит почти на каждом экране: оболочка десктопа, главная, поиск, медиатека, избранное, плейлисты, «Инфо», оба экрана плеера. Его `Ticker` запускается в `initState` и не останавливается никогда, даже на паузе: каждый кадр — полноэкранный `saveLayer` и 4 радиальных градиента. Приложение не простаивает и рисует с частотой экрана. `GlassCard` — это `BackdropFilter` с blur σ=20, и поверх движущегося фона размытие пересчитывается каждый кадр. В элементах списков (нарушение правила 5): по два на каждый результат поиска (`_SearchResultCard` и `_GlassActionButton`), по одному на каждую `_RecentTrackCard` на главной и на каждую `PlaylistCard`.
- **`SyllableKaraokeView._onAmbientTick`** вызывает `setState` каждый кадр, и весь вид караоке перестраивается (нарушение правила 3).
- **Тикеры строк `BeautifulLyricsView`** не останавливаются никогда. `setState` вызывается, только пока пружины активны, но колбэк с перебором слогов идёт каждый кадр у каждой построенной строки.
- **`PlayerScreen`** делает `ref.watch(playerProvider)` и `ref.watch(karaokeProvider)` на верхнем уровне, так что весь экран плеера перестраивается на каждое обновление позиции и на каждую строку текста.
- **`karaokeProvider` без `autoDispose`.** После первого открытия плеера он живёт всю сессию: `HapticFeedback.selectionClick()` на каждой смене строки, даже когда текста на экране нет, и поиск текста в сети на каждой смене трека (до 5 вариантов запроса × 2 провайдера; NetEase на каждый запрос делает ещё до 5 запросов текста).
- **Очередь пересобирается целиком** при `playNext` / `addToQueue` / `reloadFromLibrary`: новый `ConcatenatingAudioSource` из всех треков, `toAudioSource()` для каждого, и вся очередь уходит в MediaSession (`audio_service` → `_observeQueue` → `setQueue`).
- **Изображения:** `cacheWidth` / `cacheHeight` / `ResizeImage` нигде не используются, поэтому обложки (`thumbnails.highResUrl` при импорте) декодируются в полном размере даже в маленьких плитках.
- **`debugPrint`:** 135 вызовов в `lib/`. В релизной сборке они работают и пишут в logcat, в том числе поисковые запросы и URL.
