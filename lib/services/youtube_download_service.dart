import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import 'download_service.dart';

/// Result of a successful YouTube extraction: the saved file path plus any
/// metadata the server was willing to share via response headers.
///
/// `artist` is populated from the optional `X-Track-Artist` response header
/// (channel/uploader name), and is `null` for older servers that don't yet
/// send it. UI code should fall back to the existing "Unknown" placeholder
/// when this is absent.
class YoutubeDownloadResult {
  /// Creates a result.
  const YoutubeDownloadResult({
    required this.filePath,
    this.title,
    this.artist,
  });

  /// Absolute path to the saved audio file on disk.
  final String filePath;

  /// Optional title from the `X-Track-Title` header. Falls back to the
  /// `Content-Disposition` filename when absent.
  final String? title;

  /// Optional artist/channel name from the `X-Track-Artist` header.
  final String? artist;
}

/// YouTube audio downloader backed by a remote Flask extraction server.
///
/// Every previous in-app approach (pure-Dart `youtube_explode_dart`,
/// Chaquopy + `pytubefix`, `youtubedl-android`) broke against YouTube's
/// anti-bot defenses. This service instead POSTs the URL to a small
/// server that owns all that complexity and streams the finished audio
/// file back, so the Android side is reduced to ordinary HTTP.
///
/// Server API:
///   * `GET  /health`   — liveness check, returns `{"status":"ok"}`.
///   * `POST /download` — body `{"url": "<YouTube URL>"}`, responds with
///     the audio file as an attachment (`Content-Disposition: attachment;
///     filename="<Title>.m4a"`).
///     Optional response headers (added by the updated server, see
///     `server/server.py` in this repo for the reference implementation):
///       - `X-Track-Title` — UTF-8 video title
///       - `X-Track-Artist` — UTF-8 channel / uploader name
class YoutubeDownloadService {
  YoutubeDownloadService._();

  /// Production server. Swap per-environment via a build config if you ever
  /// need staging — for now the URL is hard-coded because the server is
  /// deliberately minimal and has no auth.
  static const String _serverUrl =
      'https://web-production-1bab4.up.railway.app';

  /// Upper bound on the full request (resolve + server-side yt-dlp +
  /// stream back). 5 minutes matches the default Railway timeout and is
  /// more than enough for normal-length music videos.
  static const Duration _timeout = Duration(minutes: 5);

  /// Downloads audio from [url] via the server and writes it into
  /// [outputDirectory]. Returns the absolute path of the saved file.
  ///
  /// Backwards-compatible legacy entry point: if the caller doesn't care
  /// about the metadata headers it can keep using this method. New code
  /// should prefer [downloadAudioWithMetadata].
  ///
  /// [onProgress] receives [DownloadProgress] updates during the transfer
  /// (same shape as desktop's `DownloadService.downloadUrlToMp3`, so UI
  /// code can consume both identically).
  static Future<String> downloadAudio({
    required String url,
    required String outputDirectory,
    void Function(DownloadProgress progress)? onProgress,
  }) async {
    final result = await downloadAudioWithMetadata(
      url: url,
      outputDirectory: outputDirectory,
      onProgress: onProgress,
    );
    return result.filePath;
  }

  /// Downloads audio AND returns any optional metadata the server provided
  /// via `X-Track-Title` / `X-Track-Artist` response headers.
  static Future<YoutubeDownloadResult> downloadAudioWithMetadata({
    required String url,
    required String outputDirectory,
    void Function(DownloadProgress progress)? onProgress,
  }) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('URL must not be empty');
    }

    onProgress?.call(
      const DownloadProgress(
        fraction: 0.05,
        message: 'Connecting to server…',
      ),
    );

    final uri = Uri.parse('$_serverUrl/download');
    final request = http.Request('POST', uri)
      ..headers['Content-Type'] = 'application/json'
      ..headers['Accept'] = '*/*'
      ..body = jsonEncode({'url': trimmed});

    final response = await request.send().timeout(_timeout);

    if (response.statusCode != 200) {
      // Consume the body so we can surface a useful error message.
      String body;
      try {
        body = await response.stream.bytesToString();
      } catch (_) {
        body = '';
      }
      throw StateError(
        'Server returned ${response.statusCode}'
        '${body.isEmpty ? '' : ': $body'}',
      );
    }

    final filename = _extractFilename(response.headers);
    final headerTitle = _decodeHeader(response.headers['x-track-title']);
    final headerArtist = _decodeHeader(response.headers['x-track-artist']);

    final outDir = Directory(outputDirectory);
    if (!await outDir.exists()) {
      await outDir.create(recursive: true);
    }

    final outPath = await _resolveUniquePath(outDir, filename);
    final file = File(outPath);
    final sink = file.openWrite();

    final total = response.contentLength ?? 0;
    var received = 0;

    onProgress?.call(
      const DownloadProgress(fraction: 0.1, message: 'Downloading…'),
    );

    try {
      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) {
          final frac = (received / total).clamp(0.1, 0.99);
          onProgress?.call(
            DownloadProgress(
              fraction: frac,
              message: '${(frac * 100).toStringAsFixed(1)}%',
            ),
          );
        }
      }
      await sink.flush();
    } catch (_) {
      await sink.close().catchError((_) {});
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {}
      rethrow;
    }
    await sink.close();

    if (!await file.exists()) {
      throw StateError('Download finished but file is missing: $outPath');
    }

    onProgress?.call(
      const DownloadProgress(fraction: 1.0, message: 'Done'),
    );
    debugPrint('YoutubeDownloadService: saved $outPath');

    return YoutubeDownloadResult(
      filePath: outPath,
      title: headerTitle,
      artist: headerArtist,
    );
  }

  /// HTTP headers are ASCII-only by spec, but yt-dlp titles/channels are
  /// regularly non-ASCII (cyrillic, emoji, ...). The reference server
  /// percent-encodes those headers (RFC 3986); decode them here so the UI
  /// gets the original string. Returns null if the header is missing or
  /// trimming yields an empty result.
  static String? _decodeHeader(String? raw) {
    if (raw == null) return null;
    String decoded;
    try {
      decoded = Uri.decodeComponent(raw);
    } catch (_) {
      decoded = raw; // Header wasn't percent-encoded — take it as-is.
    }
    final trimmed = decoded.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  /// Parses `Content-Disposition` for `filename` / `filename*` (RFC 5987).
  /// Falls back to `track.m4a` if nothing usable is present.
  static String _extractFilename(Map<String, String> headers) {
    const fallback = 'track.m4a';
    final disposition = headers['content-disposition'];
    if (disposition == null || !disposition.contains('filename')) {
      return fallback;
    }

    // RFC 5987 encoded form wins when present: filename*=UTF-8''...
    final star = RegExp(r"""filename\*\s*=\s*([^'\s]+)'[^']*'([^;]+)""",
            caseSensitive: false)
        .firstMatch(disposition);
    if (star != null) {
      try {
        final decoded = Uri.decodeComponent(star.group(2)!.trim());
        final sanitized = _sanitizeForFilename(decoded);
        if (sanitized.isNotEmpty) return sanitized;
      } catch (_) {
        // fall through to plain filename parsing
      }
    }

    final plain = RegExp(r'filename\s*=\s*"?([^";]+)"?', caseSensitive: false)
        .firstMatch(disposition);
    if (plain != null) {
      final sanitized = _sanitizeForFilename(plain.group(1)!.trim());
      if (sanitized.isNotEmpty) return sanitized;
    }

    return fallback;
  }

  /// Ensures the returned path does not collide with an existing file by
  /// appending `_1`, `_2`, … suffixes.
  static Future<String> _resolveUniquePath(Directory dir, String name) async {
    final base = p.basenameWithoutExtension(name);
    final ext = p.extension(name); // includes the leading dot, or empty
    for (var i = 0;; i++) {
      final suffix = i == 0 ? '' : '_$i';
      final candidate = p.join(dir.path, '$base$suffix$ext');
      if (!await File(candidate).exists()) return candidate;
    }
  }

  /// Replaces filesystem-unsafe characters so server-provided filenames
  /// land safely on Android / Windows / macOS.
  static String _sanitizeForFilename(String name) {
    final replaced = name.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]+'), '_');
    final collapsed = replaced.replaceAll(RegExp(r'\s+'), ' ').trim();
    return collapsed.replaceAll(RegExp(r'^[. ]+|[. ]+$'), '');
  }
}
