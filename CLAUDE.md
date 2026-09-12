# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Protogenix is a Flutter music player by Z43 Studios. It streams and downloads from YouTube and similar sources, and shows karaoke-style synced lyrics.

- Release targets are **Android and Windows**. Linux builds but has never been tested. iOS and macOS are out of scope: the `ios/` and `macos/` folders are template leftovers, don't spend effort on them. The `web/` folder exists too, but the app does not run on web, because `dart:io` `Platform` checks are used unguarded (starting in `main.dart`).
- **The repository is public** (since 2026-09-11). Never commit secrets — keystores, `key.properties`, tokens, API keys. Anything compiled into the app (`const` strings, assets) is public as well.
- The UI is dark-only (`AppTheme.dark()`, background `0xFF080810`).
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
flutter analyze                   # slow (~2 min); baseline is 7 issues, 0 errors — see known-issues.md
flutter test
flutter test test/features/player/domain/advanced_lrc_parser_test.dart
flutter test --plain-name "detects YRC format"
flutter build apk --release       # release key from android/key.properties; without it the debug key + a warning — read release.md first
flutter build windows --release
powershell -ExecutionPolicy Bypass -File tool/build_windows_installer.ps1   # installer → build/installer/ (needs Inno Setup 6)
powershell -ExecutionPolicy Bypass -File tool/release.ps1 -NotesFile docs/release-notes/vX.Y.Z.md   # full release build → build/release/vX.Y.Z/; -Publish uploads it — see release.md
powershell -ExecutionPolicy Bypass -File tool/release.ps1 -Bump patch -NotesFile docs/release-notes/vX.Y.Z.md -Publish   # bump the version, build, commit, push and publish in one go
powershell -ExecutionPolicy Bypass -File tool/youtube_health_check.ps1   # does YouTube downloading still work? -Install = daily task on Orion's PC — see dependencies.md
powershell -ExecutionPolicy Bypass -File tool/record_demo.ps1 -TrackId <id> -AudioFile <track audio> -From 63 -To 90   # demo video for the Z43 Studios site (lib/app/demo_mode.dart)
dart run tool/update_signing.dart   # update-manifest keys and signing — see release.md
dart run flutter_launcher_icons   # regenerate app icons from assets/images/icon_*.png
```

CI (`.github/workflows/ci.yml`) runs on every PR and push to master: `flutter analyze` (fails above the baseline), tests and a Windows build, and an Android arm64 build. It uses no secrets. Dependabot (`.github/dependabot.yml`) opens dependency PRs daily — see `dependencies.md`.

## Architecture

The code is split into `lib/app/` (root widget and navigation shells), `lib/core/` (theme, shared widgets, utils, services such as app paths and the YouTube clients), and `lib/features/<feature>/{data,domain,presentation}`. The features are player, library, search, importer, home, and updater. The layering is loose. For example, `library_provider.dart` sits directly in `presentation/`, and the lyrics code lives under `library/`.

### Startup (`lib/main.dart`)

The order of these steps matters:
1. On Windows/Linux, switch sqflite to the FFI backend.
2. Call `await AppPaths.init()`. It decides where databases and files live and, on desktop, migrates the databases from the old location. Nothing may touch the databases before it.
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
- For Spotify and Yandex Music it resolves the metadata, then searches YouTube and downloads the match.
- YouTube downloads try each youtube_explode client in `_clientFallbackOrder` (= `kYoutubeClientFallbackOrder` in `lib/core/services/youtube_clients.dart`, visionOS first). There is no fallback: if every client fails, the import reports an error (a Yandex Music playlist skips that track). Since August 2026 YouTube requires PO tokens from most clients, and the visionOS client is a workaround — read `known-issues.md` before touching YouTube code, and test on real tracks, not one popular video.
- Results are written to `LibraryDatabase`, with lyrics fetched during the import. Progress is reported through `ImportProgress` callbacks.

### Lyrics and karaoke

`LyricsService` queries LRCLIB, NetEase and Kugou in two stages (precise, then broad), and `LyricsMatcher` picks the result: only the same song (title, artist, duration, version), then the best format; otherwise «not found» instead of another song's lyrics. `AdvancedLrcParser` parses four formats (YRC, Enhanced LRC, synced LRC, plain); `karaokeProvider` loads and caches lyrics for the current track and tracks the active line. Contracts, selection rules and the live benchmark: `lyrics.md`.

### Search and updater

- `searchProvider` (an `AsyncNotifier`) debounces by 450ms and searches YouTube only, via youtube_explode. It returns `SearchTrack` objects so the UI is decoupled from youtube_explode types.
- The updater (`lib/features/updater/`): `UpdateChecker` downloads the signed manifest `protogenix-update.json` from the latest GitHub Release, verifies its Ed25519 signature against `kUpdateSigningKeys` (updates stay disabled while that map is empty), compares `build`, and picks the asset for the platform/ABI. `UpdateDownloader` resumes downloads and verifies SHA-256; `UpdateInstaller` opens the system APK installer on Android and silently runs the Inno Setup installer on Windows. `tool/update_signing.dart` creates the key and signs manifests. Release format, keys, hosting and the rest of the plan: `release.md`.
