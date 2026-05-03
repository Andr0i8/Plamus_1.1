# Plamus YouTube Extractor Server

Reference Flask implementation for the Railway-hosted extractor at
`https://web-production-1bab4.up.railway.app`, consumed by the mobile
client via `YoutubeDownloadService`.

This folder is informational — the server itself runs on Railway and is
deployed separately from the Flutter app. Keep this file in sync with
what's live on Railway so other contributors know the exact API contract
the client depends on.

## Why it exists

Every previous in-app YouTube extractor (`youtube_explode_dart`,
Chaquopy + `pytubefix`, `youtubedl-android`) broke against YouTube's
anti-bot defenses. Moving the extraction server-side (where we control
the Python runtime, cookies, and IP) is the only sustainable option.

## What the client expects

- `POST /download` with JSON body `{"url": "<YouTube URL>"}`.
- `200 OK` with the audio file as a streamed attachment
  (`Content-Disposition: attachment; filename="<Title>.m4a"`).
- **New (BUG 2):** optional response headers
  - `X-Track-Title` — percent-encoded video title.
  - `X-Track-Artist` — percent-encoded uploader / channel name.

  The client decodes these with `Uri.decodeComponent` and passes them
  into `LibraryService.registerTrackFile(artist: ..., title: ...)` so
  downloaded tracks show the real channel name instead of "Unknown".

- **New (BUG 5):** non-YouTube URLs return `400 Bad Request` with
  `{"error": "Only YouTube links are supported"}`. The client also
  filters before making the request, so the server-side check is
  defense-in-depth for older app builds still in the wild.

## Deploying updates

1. Edit `server.py` locally and test with `python server.py`.
2. Push to the Railway service that hosts this extractor.
3. Verify with:
   ```bash
   curl https://web-production-1bab4.up.railway.app/health
   # {"status":"ok"}
   curl -sI -X POST \
        -H 'Content-Type: application/json' \
        -d '{"url":"https://www.youtube.com/watch?v=dQw4w9WgXcQ"}' \
        https://web-production-1bab4.up.railway.app/download \
        | grep -Ei 'x-track-(title|artist)|content-disposition'
   ```

If `X-Track-Artist` is not present, older deployments are running; the
client will fall back to "Unknown" as it always has.
