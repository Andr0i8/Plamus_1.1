Plamus binary bundle (Desktop only)
====================================

These binaries are ONLY needed for DESKTOP (Windows/Linux) builds.
Android and iOS use AudioDownloadService (pure Dart) instead.

Before building a DESKTOP release, copy into this folder:

  - yt-dlp.exe   (official Windows build from https://github.com/yt-dlp/yt-dlp/releases)
  - ffmpeg.exe   (static build, e.g. from https://www.gyan.dev/ffmpeg/builds/)

DO NOT place large binaries here when building for Android — they will be
bundled into the APK and inflate the app size by ~150 MB.

For Android builds, this folder should contain only this README.
The app extracts desktop binaries to the user's AppData on first run.

If binaries are missing on desktop, URL download and video-to-audio
conversion will show a clear error, but local audio playback still works.
