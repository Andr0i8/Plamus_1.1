# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Plamus is an offline-first, cross-platform music player built with Flutter (Android + Windows desktop). It features local library management, YouTube audio extraction (pure Dart), and a minimalist UI with glass morphism design.

## Development Commands

### Running the app
```bash
flutter run -d windows    # Desktop
flutter run -d android    # Android (connected device/emulator)
```

### Testing
```bash
flutter test
```

### Building
```bash
# Desktop
flutter build windows --release

# Android — split APKs for smaller size
flutter build apk --split-per-abi

# Android — App Bundle for Play Store
flutter build appbundle
```

### Code analysis
```bash
flutter analyze
```

### Dependency management
```bash
flutter pub get
flutter pub upgrade
```

## Architecture

### Audio Backend
- **Android/iOS**: `just_audio` with `just_audio_background` for background playback + media notifications
- **Windows/Linux**: `just_audio` with `media_kit` backend (`JustAudioMediaKit.ensureInitialized()`)
- After changing audio dependencies, perform a **full cold restart** (not hot reload)

### Database Layer
- SQLite via `sqflite` on mobile, `sqflite_common_ffi` on desktop
- Must initialize FFI in `main()` for desktop: `sqfliteFfiInit(); databaseFactory = databaseFactoryFfi;`
- Schema: `tracks`, `playlists`, `playlist_tracks`, `history`
- Database file: `plamus.db` in application support directory

### State Management
- Provider pattern for reactive state
- Three main providers:
  - `LibraryService`: tracks, playlists, SQLite coordination
  - `AudioPlayerService`: playback queue, shuffle, repeat, volume
  - `ThemeController`: light/dark theme toggle

### Media Download Pipeline (Android)
1. **YouTube URLs**: `AudioDownloadService` uses `youtube_explode_dart` (pure Dart, zero native overhead)
   - Resolves video metadata + stream manifest
   - Picks highest-bitrate audio-only stream (prefers AAC/m4a, falls back to Opus/webm)
   - Streams bytes to disk with real-time progress
   - No ffmpeg, no yt-dlp, no native binaries
2. **Direct audio URLs**: `AudioDownloadService` uses `http` package to stream-download
3. **Local files**: `MediaIngestService` copies audio files into library folder
4. **Registration**: `LibraryService.registerTrackFile()` indexes the file path in SQLite
5. Supported audio formats: MP3, WAV, FLAC, M4A, AAC, OGG, OPUS, WEBM, WMA

### Media Download Pipeline (Desktop)
1. **YouTube/URLs**: `DownloadService` runs bundled `yt-dlp.exe` (supports many sites beyond YouTube)
2. **Local files**: `MediaIngestService` copies audio or extracts from video via ffmpeg
3. **Binary Dependencies**: `BinaryService` extracts `yt-dlp.exe` and `ffmpeg.exe` from `assets/bin/`
   - **Only needed for desktop builds** — do NOT place large binaries when building Android
   - yt-dlp flags: `--no-playlist -x --audio-format mp3 --audio-quality 0`
   - ffmpeg flags: `-vn -codec:a libmp3lame -q:a 0` (VBR quality 0)

### UI Structure
- **Desktop**: `PlamusShell` — sidebar navigation + animated content + `GlassPlayerBar`
- **Mobile**: `PlamusShellMobile` — bottom navigation + `MobileMiniPlayer`
- Sections: Home (library), Search/Import, Liked Songs, History, Playlist Detail
- Theme: custom `PlamusTheme` with light/dark variants, glass morphism effects

### File Paths
- Library directory: platform equivalent of app support via `path_provider`
- Database: `plamus.db` in application support directory
- Binaries (desktop only): `bin/yt-dlp.exe`, `ffmpeg.exe` in app support

## Key Services

### AudioDownloadService (NEW — Android/iOS)
- Unified pure-Dart audio download service
- YouTube: `youtube_explode_dart` for stream resolution and download
- Direct URLs: HTTP streaming via `http` package
- Saves playback-ready files (.m4a, .mp3, .ogg, etc.)
- Real-time progress callbacks + status logging
- Zero native dependencies, zero APK size impact

### AudioPlayerService
- Wraps `just_audio` with queue management, repeat modes
- Repeat modes: off, all (loop queue), one (loop single track)
- Records play history to SQLite on track load
- Updates track duration in DB after first play if unknown

### LibraryService
- CRUD for tracks and playlists
- Smart lists: liked tracks, recent history (last 50 plays)
- Track operations: rename (updates file + DB), export, reveal in Explorer, delete
- Playlist operations: create, rename, delete, add/remove tracks

### DownloadService (Desktop only)
- Runs yt-dlp as child process with 45-minute timeout
- Parses `[download] X%` from stderr for progress UI
- Returns path to downloaded MP3 in library directory

### MediaIngestService
- Copies audio files into library folder
- On desktop: can also extract audio from video via ffmpeg
- On mobile: audio files only (no video transcoding)
- Ensures unique filenames with `_1`, `_2` suffixes if collision

## Android Build Optimization
- **No bundled binaries**: Android uses pure-Dart `youtube_explode_dart` (no ffmpeg, no yt-dlp)
- **Split APKs**: `build.gradle.kts` configured for per-ABI splits (arm64-v8a, armeabi-v7a)
- **R8 shrinking**: `isMinifyEnabled = true` + `isShrinkResources = true` in release builds
- **ProGuard rules**: `android/app/proguard-rules.pro` preserves Flutter + audio service classes
- **Asset exclusion**: `androidResources.ignoreAssetsPatterns` excludes `.exe` and `yt-dlp_*` files
- **Build commands**:
  - `flutter build apk --split-per-abi` — split APKs for direct distribution
  - `flutter build appbundle` — App Bundle for Play Store (automatic per-device optimization)

## Common Pitfalls
- **Audio not working (desktop)**: ensure `JustAudioMediaKit.ensureInitialized()` ran
- **Audio not working (mobile)**: ensure `JustAudioBackground.init()` ran in main()
- **yt-dlp/ffmpeg missing (desktop)**: check `BinaryService.lastResolution.errors`
- **APK too large**: ensure `assets/bin/` does not contain .exe files (should only have README.txt)
- **File in use errors**: Windows locks open files; stop playback before renaming/deleting
- **Hot reload issues**: audio backend changes require full restart
