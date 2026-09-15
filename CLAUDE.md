# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Protogenix is a Flutter music player by Z43 Studios. It streams and downloads from YouTube and similar sources, and shows karaoke-style synced lyrics.

- Release targets are **Android and Windows**. Linux builds but has never been tested. iOS and macOS are out of scope: the `ios/` and `macos/` folders are template leftovers, don't spend effort on them. The `web/` folder exists too, but the app does not run on web, because `dart:io` `Platform` checks are used unguarded (starting in `main.dart`).
- **The repository is public** (since 2026-09-11). Never commit secrets — keystores, `key.properties`, tokens, API keys. Anything compiled into the app (`const` strings, assets) is public as well.
- The UI is dark-only (`AppTheme.dark()`, background `0xFF080810`). The accent colour is the cover palette (`paletteProvider`), not `colorScheme.primary` (a fixed purple seed). Shared styled widgets live in `lib/core/widgets/`: `GlassPanel` (dark glass for overlays), `showGlassConfirm` (confirmations — don't use `AlertDialog`), `AccentButton` (primary full-width action — don't use `ElevatedButton`), `ChipButton` (pills), `SectionCard` (titled cards on the Settings and Info pages), `GlassBackButton` (back button on full-screen pages). Don't put a `Tooltip` in anything placed in `MaterialApp.builder` (the import overlay): there is no `Overlay` above the `Navigator`.
- There is no l10n. All user-facing strings are hardcoded in Russian, and most code comments are Russian as well. Keep new strings consistent with that.
- Most changes arrive as PRs from the Jules bot (`google-labs-jules[bot]`). Its learning logs live in `.jules/`; their rules are folded into `.claude/rules/`.
- `repomix-output.xml` in the repo root, if present, is a generated snapshot of the whole repo. Ignore it when searching.

## Communication

You work with **Orion** — solo developer and the only person on this project.
Note that most PRs come from the Jules bot; treat its output with the same
skepticism as any generated code.

Speak Russian. Friendly and clear, but direct: if something in the code is broken,
fragile, or a bad pattern, say so plainly instead of quietly working around it.
Explain *why*, not just *what*.

Prefer real fixes over patches. If the honest fix is bigger than a quick workaround,
say so and let Orion choose — don't silently pick the easy patch and call it done.
A workaround is fine only when you name it as one and say what it defers.

## Where to log work

After any significant task, add an entry at the top of `docs/CHANGELOG_CLAUDE.md` (date, what, why, what you deliberately left alone); `.jules/` is Jules's topic-based lesson log — read it, never write to it.

## Topic rules (`.claude/rules/`)

Written in Russian. Each file has `paths:` frontmatter, so it loads automatically only when you read a matching file — not every session. Commands that read no files (building, `pub upgrade`) don't trigger that, so read the file yourself before:

| File | Read before |
|---|---|
| `release.md` | **any release build, signing change, version bump, installer/updater change, or release hosting — the highest-risk area** |
| `dependencies.md` | `pub add` / `pub upgrade`, Dependabot PRs, or touching `pubspec.yaml` / `netease_provider.dart` / `.github/` |
| `data.md` | DB schema changes, anything that modifies library tracks or playlists, where data is stored |
| `performance.md` | UI widgets and anything that watches `playerProvider` |
| `lyrics.md` | lyrics search, the LRC parser, karaoke |
| `security.md` | the importer, file names from the network, user-facing error messages, secrets |
| `known-issues.md` | writing tests, judging `flutter analyze` output, EQ, the visualizer, web — what not to fix in passing |

A lesson learned during a task goes into the matching rules file; the changelog entry just points to it.

## Commands

```bash
flutter pub get
flutter run -d windows            # or: android, linux, macos
flutter analyze                   # slow (~2 min); baseline is 6 issues, 0 errors — see known-issues.md
flutter test
flutter test test/features/player/domain/advanced_lrc_parser_test.dart
flutter test --plain-name "detects YRC format"
flutter build apk --release       # release key from android/key.properties; without it the debug key + a warning — read release.md first
flutter build windows --release
powershell -ExecutionPolicy Bypass -File tool/build_windows_installer.ps1   # clean Windows build + installer → build/installer/ (needs Inno Setup 6; -SkipFlutterBuild reuses the build)
powershell -ExecutionPolicy Bypass -File tool/release.ps1 -NotesFile docs/release-notes/vX.Y.Z.md   # full release build → build/release/vX.Y.Z/; -Publish uploads it — see release.md
powershell -ExecutionPolicy Bypass -File tool/release.ps1 -Bump patch -NotesFile docs/release-notes/vX.Y.Z.md -Publish   # bump the version, build, commit, push and publish in one go
powershell -ExecutionPolicy Bypass -File tool/youtube_health_check.ps1   # does YouTube downloading still work? -Install = daily task on Orion's PC — see dependencies.md
powershell -ExecutionPolicy Bypass -File tool/record_demo.ps1 -TrackId <id> -AudioFile <track audio> -From 63 -To 90   # demo video for the Z43 Studios site (lib/app/demo_mode.dart)
dart run tool/update_signing.dart   # update-manifest keys and signing — see release.md
dart run flutter_launcher_icons   # regenerate app icons from assets/images/icon_*.png
```

CI (`.github/workflows/ci.yml`) runs on every PR and push to master: `flutter analyze` (fails above the baseline), tests and a Windows build, and an Android arm64 build. It uses no secrets. Dependabot (`.github/dependabot.yml`) opens dependency PRs daily — see `dependencies.md`.

## Architecture

The code is split into `lib/app/` (root widget and navigation shells), `lib/core/` (theme, shared widgets, utils, services such as app paths and the YouTube clients), and `lib/features/<feature>/{data,domain,presentation}`. The features are player, library, search, importer, home, updater, settings, discord (Discord status on Windows) and listen («Слушать в Protogenix» links). The layering is loose. For example, `library_provider.dart` sits directly in `presentation/`, and the lyrics code lives under `library/`.

### Startup (`lib/main.dart`)

The order of these steps matters:
1. On Windows/Linux, switch sqflite to the FFI backend.
2. Call `await AppPaths.init()`. It decides where databases and files live and, on desktop, migrates the databases from the old location. Nothing may touch the databases before it. Right after it, `LocalTagsMigration.runOnce()` re-reads tags once for local files imported before 1.1 (before the player loads the queue).
3. On mobile, enable edge-to-edge.
4. On desktop, set up `window_manager` (hidden native title bar, minimum size 1000×700).
5. On Windows/Linux, call `JustAudioMediaKit.ensureInitialized()`.
6. Call `await initAudioService()`. This must happen before `runApp`, because it assigns the global `audioHandler`.
7. Call `runApp`.

### Navigation shells (`lib/app/app_shell.dart`)

All shells share one `_tabIndexProvider` and one `_screens` list (Home / Search / Library in an `IndexedStack`).

- **Desktop** (`_DesktopShell`): a 240px sidebar, a resizable right panel (lyrics or queue), and `DesktopBottomPlayer`. The expanded player replaces the whole shell through local state, not a route. The custom `WindowTitleBar` is injected in `MaterialApp.builder` (`app.dart`).
- **Mobile** uses `FoldLayout` (`kFoldBreakpoint = 600`):
  - Compact: bottom bar, `MiniPlayer`, and `PlayerScreen` as a modal bottom sheet.
  - Expanded (tablet or Fold): a navigation rail, with `ExpandedPlayerScreen` opened via `Navigator.push`.
  - The compact shell closes the open modal when the width crosses the breakpoint.

### Playback

- `player/data/audio_handler.dart` defines the global `late AudioHandler audioHandler`. `ProtogenixAudioHandler` (an audio_service `BaseAudioHandler`) wraps a single just_audio `AudioPlayer` playing a `ConcatenatingAudioSource`. On Android an `AndroidEqualizer` is added to the audio pipeline; `PlayerNotifier` drives it and persists its settings (`eq_settings_store.dart`).
- `playerProvider` (`PlayerNotifier`) is the UI's single source of truth.
  - It casts `audioHandler` and subscribes directly to the `AudioPlayer` streams.
  - Every queue change (`playNext`, `addToQueue`) rebuilds the whole playlist through `loadPlaylist`.
  - On startup it loads the entire library as the queue.
  - Shuffle is done by `PlayerNotifier` itself (`player/domain/queue_shuffle.dart`): the queue is reordered (current track first) and reloaded at the same position. Never enable just_audio's own shuffle mode: on Windows `just_audio_media_kit` shuffles mpv's playlist and then reports indices in the shuffled order (`known-issues.md`).
- While the app is hidden (`core/services/app_visibility.dart`), lyrics search, active-line tracking and cover-palette extraction wait and catch up when it returns. Lyric-line haptics live only in `beautiful_lyrics_view.dart` and fire only while the app is resumed.
- `TrackModel.toAudioSource()` (`player/domain/track_model.dart`) chooses the audio source:
  - A network `filePath` pointing to a YouTube video goes the YouTube route below; any other http(s) URL is played directly on desktop, or through `LockCachingAudioSource` in `AppPaths.audioCacheDir` on mobile.
  - Otherwise the local file, if it exists.
  - An 11-character YouTube ID without a local file: youtube_explode's best mp4 audio stream (visionOS client first, see `lib/core/services/youtube_clients.dart`), checked with a HEAD request. If that fails, `assets/mock/silence.mp3`: there is no fallback (the Invidious proxy was removed 2026-09-12, see `known-issues.md`). `toAudioSource()` must never throw — `loadPlaylist` awaits the sources of the whole queue with `Future.wait`.
  - Otherwise `assets/mock/silence.mp3`.

### Data

Two separate sqflite databases: `LibraryDatabase` (`protogenix.db`, tracks) and `PlaylistDatabase` (`protogenix_playlists.db`, playlists and favorites). `LibraryTrack` (the DB model) converts to `TrackModel` (the player model) via `toTrackModel()`. All storage paths come from `AppPaths` (`lib/core/services/app_paths.dart`); on Windows data lives in `%LOCALAPPDATA%\Z43 Studios\Protogenix`. The library and the player are not linked reactively — read `data.md` before touching any of this.

### Import (`importer/data/importer_service.dart`)

`ImporterService.importFromUrl` dispatches by URL type: Spotify, Yandex Music, YouTube, SoundCloud, or a direct audio link. SoundCloud is only a stub that reports «SoundCloud в следующем обновлении».
- For Spotify and Yandex Music it resolves the metadata, then searches YouTube and downloads the match. Which video counts as a match is decided by `youtube_match.dart`: same title, same artist, same version, with the exact duration and the artist's own channel first. If the best pick of the «Artist - Title» search isn't from the artist's channel, a second «topic» search runs and both result lists are ranked together (`findYoutubeUpload`). A track without a match is skipped rather than replaced by a cover or a live version (`known-issues.md`). Yandex Music goes through `api.music.yandex.net` without a token (`yandex_music.dart`: track, album and playlist links on any `music.yandex.*` domain); the API answers only from countries where Yandex Music works, so behind a foreign VPN exit the import reports 451 — see `known-issues.md`.
- Local files (`importLocalFiles`) get tags and the embedded cover from `audio_metadata_reader` (`local_tags.dart`) and an id from a content hash (`data.md`). On desktop, files and folders can also be dropped onto the window (`desktop_drop_import.dart`).
- On Android, «Найти музыку на телефоне» lists MediaStore through a method channel in `MainActivity.kt` (`device_music.dart`) and adds the tracks in place, without copying (`source: 'device'`; deleting such a track never deletes the file).
- All of these, and «В медиатеку» in search, run in the background through `ImportManager` (`importer/presentation/import_manager.dart`), one job at a time; the rest wait in an in-memory queue (the same link is not queued twice, «Остановить» clears the queue). The sheet can be closed, and `ImportStatusOverlay` (placed in `MaterialApp.builder`) shows progress and «Остановить». `ImportControl` stops between tracks and reports each saved track, so the library refreshes during the import. An interrupted URL import is offered for resume on the next start; re-importing a Yandex link skips tracks already in the library without searching YouTube (matched by the stored Yandex title, artists and album, `yandex_library_index.dart`) and fills the same-named playlist.
- YouTube downloads try each youtube_explode client in `_clientFallbackOrder` (= `kYoutubeClientFallbackOrder` in `lib/core/services/youtube_clients.dart`, visionOS first). There is no fallback: if every client fails, the import reports an error (a Yandex Music playlist skips that track). Since August 2026 YouTube requires PO tokens from most clients, and the visionOS client is a workaround — read `known-issues.md` before touching YouTube code, and test on real tracks, not one popular video.
- Results are written to `LibraryDatabase`, with lyrics fetched during the import. Progress is reported through `ImportProgress` callbacks.

### Lyrics and karaoke

`LyricsService` queries LRCLIB, NetEase and Kugou in two stages (precise, then broad), and `LyricsMatcher` picks the result: only the same song (title, artist, duration, version), then the best format; otherwise «not found» instead of another song's lyrics. `AdvancedLrcParser` parses four formats (YRC, Enhanced LRC, synced LRC, plain); `karaokeProvider` loads and caches lyrics for the current track and tracks the active line. Contracts, selection rules and the live benchmark: `lyrics.md`.

### Search and updater

- `searchProvider` (an `AsyncNotifier`) debounces by 450ms and searches YouTube only, via youtube_explode. It returns `SearchTrack` objects so the UI is decoupled from youtube_explode types.
- The updater (`lib/features/updater/`): `UpdateChecker` downloads the signed manifest `protogenix-update.json` from the latest GitHub Release, verifies its Ed25519 signature against `kUpdateSigningKeys` (updates stay disabled while that map is empty), compares `build`, and picks the asset for the platform/ABI. `UpdateDownloader` resumes downloads and verifies SHA-256; `UpdateInstaller` opens the system APK installer on Android and silently runs the Inno Setup installer on Windows. `tool/update_signing.dart` creates the key and signs manifests. The Info page (`library/presentation/screens/info_screen.dart`) shows the real version and the update status and can re-check (`UpdateNotifier.checkNow`; `UpdateChecker.checkDetailed` tells «up to date» from «couldn't check»). Release format, keys, hosting and the rest of the plan: `release.md`.

### Settings, Discord status and «Слушать в Protogenix»

- **Settings** (`features/settings/presentation/settings_screen.dart`) open from the gear on the phone home screen and from «Настройки» at the bottom of the desktop sidebar. They hold «Слоги / Строки», the Discord switch (Windows), the equalizer (Android) and «О приложении», which opens the Info page. Values live in `settings.json` (`data.md`).
- **Discord status** (`features/discord/`, Windows only): `DiscordIpc` talks to the local Discord client over `\\?\pipe\discord-ipc-N`. `discordPresenceProvider` (watched in `app.dart`) listens to `playerProvider` and sends a «Listening» activity with a «Слушать в Protogenix» button, at most once every 4 s. Android and the other limits: `known-issues.md`.
- **Listen links** (`features/listen/`): `protogenix://listen?v=&t=&a=&d=`, reached from the Discord button through the Z43 Studios site page `/listen`. `main(List<String> args)` hands launch arguments to `setLaunchArguments`; a running app receives links over the `z43.studios.protogenix/links` channel (Windows: a second launch forwards them via `WM_COPYDATA`; Android: `MainActivity`). `handleListenLink` always asks before playing or downloading. Links are external input — `security.md`; scheme registration in the installer and deploying the site before the app release — `release.md`.
