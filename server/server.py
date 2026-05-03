"""Reference Flask server for Plamus' YouTube audio extractor.

This file does NOT run inside the Flutter app — it lives in this repo as
the source of truth for what the Plamus mobile client expects from the
Railway-hosted downloader at
`https://web-production-1bab4.up.railway.app`.

To roll out BUG 2's channel-name metadata, replace Railway's `server.py`
with this file (or cherry-pick the `X-Track-Title` / `X-Track-Artist`
response headers into the existing deployment) and redeploy.

Endpoints
---------
* ``GET /health``   — liveness probe, returns ``{"status": "ok"}``.
* ``POST /download`` — body: ``{"url": "<YouTube URL>"}``. On success the
  response is the extracted audio file as an attachment
  (``Content-Disposition: attachment; filename="<Title>.m4a"``) with the
  following additional headers so the client can populate
  track metadata (see ``YoutubeDownloadService`` in the Dart codebase):

    X-Track-Title:  <video title, percent-encoded>
    X-Track-Artist: <uploader / channel name, percent-encoded>

Percent-encoding is used because raw HTTP headers are ASCII-only by spec
and real YouTube titles routinely contain non-ASCII characters (cyrillic,
emoji, math symbols, ...). The Dart client decodes these headers with
``Uri.decodeComponent`` — see ``YoutubeDownloadService._decodeHeader``.

Validation
----------
Any URL that is not a YouTube URL returns ``400`` with a JSON body
``{"error": "Only YouTube links are supported"}`` so the client doesn't
pay for a pointless download and can surface a clear inline message
(BUG 5).

Dependencies (``requirements.txt`` on Railway):
    flask
    yt-dlp
"""

from __future__ import annotations

import os
import re
import tempfile
from typing import Optional
from urllib.parse import quote

from flask import Flask, jsonify, request, send_file

try:
    import yt_dlp  # type: ignore
except ImportError as exc:  # pragma: no cover
    raise SystemExit(
        "yt-dlp is required. Install with `pip install yt-dlp`."
    ) from exc

app = Flask(__name__)

# Matches youtube.com, www.youtube.com, m.youtube.com, music.youtube.com,
# youtu.be, and youtube-nocookie.com variants. Keep this aligned with
# ``AudioDownloadService.isYouTubeUrl`` on the client side.
_YOUTUBE_HOST_RE = re.compile(
    r"""^https?://
        (?:[a-z0-9-]+\.)?            # optional subdomain(s)
        (?:youtube\.com |
           youtu\.be     |
           youtube-nocookie\.com)
        /""",
    re.IGNORECASE | re.VERBOSE,
)


def _is_youtube_url(url: str) -> bool:
    return bool(_YOUTUBE_HOST_RE.match(url.strip()))


@app.route("/health", methods=["GET"])
def health():
    return jsonify({"status": "ok"})


@app.route("/download", methods=["POST"])
def download():
    payload = request.get_json(silent=True) or {}
    url: Optional[str] = payload.get("url")
    if not isinstance(url, str) or not url.strip():
        return jsonify({"error": "Missing 'url' in JSON body"}), 400

    url = url.strip()

    # BUG 5: reject non-YouTube URLs server-side so the client doesn't
    # receive broken audio bytes when someone pastes a VK / SoundCloud /
    # generic link. The client also pre-filters, but keep this here as a
    # defense-in-depth check for older app builds.
    if not _is_youtube_url(url):
        return (
            jsonify({"error": "Only YouTube links are supported"}),
            400,
        )

    with tempfile.TemporaryDirectory() as tmpdir:
        out_template = os.path.join(tmpdir, "%(title)s.%(ext)s")
        ydl_opts = {
            "format": "bestaudio[ext=m4a]/bestaudio/best",
            "outtmpl": out_template,
            "noplaylist": True,
            "quiet": True,
            "no_warnings": True,
        }

        try:
            with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                info = ydl.extract_info(url, download=True)
                filename = ydl.prepare_filename(info)
        except Exception as exc:  # noqa: BLE001 — surface the message to the client
            return jsonify({"error": str(exc)}), 500

        title = (info.get("title") or "track").strip()
        # yt-dlp populates "uploader" for most YouTube videos; fall back
        # to "channel" (used for some YouTube Music items) and finally an
        # empty string when neither is available. The client treats an
        # empty value as "Unknown" (BUG 2).
        artist = (
            info.get("uploader")
            or info.get("channel")
            or info.get("creator")
            or ""
        ).strip()

        response = send_file(
            filename,
            as_attachment=True,
            download_name=os.path.basename(filename),
        )

        # RFC 5987 encoded form so non-ASCII filenames survive.
        response.headers["Content-Disposition"] = (
            "attachment; "
            f'filename="{os.path.basename(filename)}"; '
            f"filename*=UTF-8''{quote(os.path.basename(filename))}"
        )

        # Metadata headers consumed by the Dart client (BUG 2).
        # Percent-encoded so the values stay within the ASCII-only HTTP
        # header grammar.
        response.headers["X-Track-Title"] = quote(title, safe="")
        if artist:
            response.headers["X-Track-Artist"] = quote(artist, safe="")

        return response


if __name__ == "__main__":
    port = int(os.environ.get("PORT", 8080))
    app.run(host="0.0.0.0", port=port)
