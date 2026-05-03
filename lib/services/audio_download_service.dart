import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import 'download_service.dart';
import 'youtube_download_service.dart';

/// Result of a successful mobile download: where the file landed on disk
/// plus any best-effort metadata recovered along the way.
///
/// For YouTube URLs the server may include `X-Track-Title` and
/// `X-Track-Artist` response headers; both fields are `null` when those
/// headers are absent (e.g. older server build) or for direct audio URLs
/// where no metadata is available.
class AudioDownloadResult {
  /// Creates a result.
  const AudioDownloadResult({
    required this.filePath,
    this.title,
    this.artist,
  });

  /// Absolute path to the saved audio file on disk.
  final String filePath;

  /// Optional title (server-provided, YouTube only).
  final String? title;

  /// Optional artist / channel name (server-provided, YouTube only).
  final String? artist;
}

/// Unified mobile audio download service (Android / iOS).
///
/// Two code paths:
///
///   * **YouTube URLs** → delegated to [YoutubeDownloadService], which
///     POSTs to our Flask extraction server. Every previous in-app
///     approach (`youtube_explode_dart`, Chaquopy + `pytubefix`,
///     `youtubedl-android`) failed against current YouTube defenses, so
///     the extractor now lives server-side.
///   * **Direct audio URLs** → streamed to disk with the [http] package.
///     Works for any URL that returns audio bytes (MP3, M4A, OGG, …).
///
/// Desktop uses [DownloadService] (yt-dlp binary) instead — see
/// `import_panel.dart` for the routing.
class AudioDownloadService {
  AudioDownloadService._();

  static final AudioDownloadService instance = AudioDownloadService._();

  /// Backwards-compatible: returns just the saved file path.
  ///
  /// New callers should prefer [downloadAudioWithMetadata] so they can
  /// pick up the `X-Track-Artist` channel name.
  Future<String> downloadAudio({
    required String url,
    required String outputDirectory,
    void Function(double fraction)? onProgress,
    void Function(String message)? onLog,
  }) async {
    final result = await downloadAudioWithMetadata(
      url: url,
      outputDirectory: outputDirectory,
      onProgress: onProgress,
      onLog: onLog,
    );
    return result.filePath;
  }

  /// Downloads [url] into [outputDirectory] and returns the saved path
  /// plus any title/artist metadata the server provided.
  ///
  /// [onProgress] receives values in `[0.0, 1.0]`. A terminal `1.0` is
  /// guaranteed on success.
  ///
  /// [onLog] receives short human-readable status strings for UI display.
  ///
  /// Throws on any failure; the message is suitable for an inline error.
  Future<AudioDownloadResult> downloadAudioWithMetadata({
    required String url,
    required String outputDirectory,
    void Function(double fraction)? onProgress,
    void Function(String message)? onLog,
  }) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('URL must not be empty');
    }

    if (isYouTubeUrl(trimmed)) {
      return _downloadFromYouTube(
        url: trimmed,
        outputDirectory: outputDirectory,
        onProgress: onProgress,
        onLog: onLog,
      );
    }

    final filePath = await _downloadDirectUrl(
      url: trimmed,
      outputDirectory: outputDirectory,
      onProgress: onProgress,
      onLog: onLog,
    );
    return AudioDownloadResult(filePath: filePath);
  }

  // ---------------------------------------------------------------------------
  // YouTube — delegated to the Railway-hosted extractor
  // ---------------------------------------------------------------------------

  /// Bridges [YoutubeDownloadService]'s [DownloadProgress] updates back to
  /// the `(double fraction, String message)` pair the UI already consumes,
  /// and forwards any title/artist metadata to the caller.
  Future<AudioDownloadResult> _downloadFromYouTube({
    required String url,
    required String outputDirectory,
    void Function(double fraction)? onProgress,
    void Function(String message)? onLog,
  }) async {
    final result = await YoutubeDownloadService.downloadAudioWithMetadata(
      url: url,
      outputDirectory: outputDirectory,
      onProgress: (progress) {
        onProgress?.call(progress.fraction);
        if (progress.message.isNotEmpty) onLog?.call(progress.message);
      },
    );
    return AudioDownloadResult(
      filePath: result.filePath,
      title: result.title,
      artist: result.artist,
    );
  }

  // ---------------------------------------------------------------------------
  // Direct URL download via http
  // ---------------------------------------------------------------------------

  /// Downloads a direct audio file from [url] (non-YouTube).
  ///
  /// Supports any URL that points to a streamable audio file (MP3, M4A, OGG,
  /// FLAC, WAV, AAC, WEBM). The response is streamed to disk with progress
  /// based on Content-Length when available.
  Future<String> _downloadDirectUrl({
    required String url,
    required String outputDirectory,
    void Function(double fraction)? onProgress,
    void Function(String message)? onLog,
  }) async {
    onProgress?.call(0.0);
    onLog?.call('Connecting\u2026');

    final uri = Uri.parse(url);
    final client = http.Client();

    try {
      final request = http.Request('GET', uri);
      final response = await client.send(request);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'Server returned ${response.statusCode} for $url',
          uri: uri,
        );
      }

      // Determine filename and extension from URL or Content-Type header.
      final ext = _extensionFromResponse(uri, response);
      final baseName = _baseNameFromUri(uri);

      final destPath = await _resolveUniquePath(
        directory: outputDirectory,
        baseName: baseName,
        extension: ext,
      );

      final totalBytes = response.contentLength ?? 0;
      onLog?.call('Downloading audio\u2026');

      final file = File(destPath);
      final sink = file.openWrite();
      var received = 0;

      try {
        await for (final chunk in response.stream) {
          sink.add(chunk);
          received += chunk.length;
          if (totalBytes > 0) {
            final fraction = (received / totalBytes).clamp(0.0, 0.99);
            onProgress?.call(fraction);
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

      if (!await File(destPath).exists()) {
        throw StateError('Download finished but file is missing: $destPath');
      }

      onProgress?.call(1.0);
      onLog?.call('Done');
      debugPrint('AudioDownloadService: saved $destPath');
      return destPath;
    } finally {
      client.close();
    }
  }

  // ---------------------------------------------------------------------------
  // URL classification
  // ---------------------------------------------------------------------------

  /// Whether [url] looks like a YouTube video URL or ID.
  static bool isYouTubeUrl(String url) {
    final lower = url.toLowerCase();
    return lower.contains('youtube.com') ||
        lower.contains('youtu.be') ||
        lower.contains('youtube-nocookie.com') ||
        // Bare 11-char video IDs (e.g. "dQw4w9WgXcQ")
        RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(url.trim());
  }

  /// Common audio file extensions for direct-link detection.
  static const Set<String> _audioExtensions = {
    'mp3', 'm4a', 'aac', 'ogg', 'opus', 'flac', 'wav', 'wma', 'webm',
  };

  /// Whether [url] appears to be a direct link to an audio file.
  static bool isDirectAudioUrl(String url) {
    try {
      final path = Uri.parse(url).path.toLowerCase();
      return _audioExtensions.any((ext) => path.endsWith('.$ext'));
    } catch (_) {
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Infers file extension from the HTTP response or falls back to the URL
  /// path. Returns extension without the leading dot.
  static String _extensionFromResponse(
    Uri uri,
    http.StreamedResponse response,
  ) {
    // Try Content-Type header first.
    final contentType = response.headers['content-type'] ?? '';
    const mimeToExt = {
      'audio/mpeg': 'mp3',
      'audio/mp3': 'mp3',
      'audio/mp4': 'm4a',
      'audio/aac': 'aac',
      'audio/ogg': 'ogg',
      'audio/opus': 'opus',
      'audio/flac': 'flac',
      'audio/wav': 'wav',
      'audio/x-wav': 'wav',
      'audio/webm': 'webm',
      'audio/x-ms-wma': 'wma',
    };
    for (final entry in mimeToExt.entries) {
      if (contentType.contains(entry.key)) return entry.value;
    }

    // Fall back to URL path extension.
    final urlExt = p.extension(uri.path).replaceFirst('.', '').toLowerCase();
    if (_audioExtensions.contains(urlExt)) return urlExt;

    // Default to mp3 as a safe fallback.
    return 'mp3';
  }

  /// Extracts a reasonable base filename from a URI path.
  static String _baseNameFromUri(Uri uri) {
    var base = p.basenameWithoutExtension(uri.path);
    base = _sanitizeForFilename(base);
    return base.isEmpty ? 'audio' : base;
  }

  /// Returns a path under [directory] that does not currently exist.
  /// Uses `_1`, `_2`, ... suffixes to avoid collisions.
  static Future<String> _resolveUniquePath({
    required String directory,
    required String baseName,
    required String extension,
  }) async {
    final dir = Directory(directory);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    for (var i = 0;; i++) {
      final suffix = i == 0 ? '' : '_$i';
      final candidate = p.join(dir.path, '$baseName$suffix.$extension');
      if (!await File(candidate).exists()) {
        return candidate;
      }
    }
  }

  /// Replaces filesystem-unsafe characters for cross-platform filenames.
  static String _sanitizeForFilename(String name) {
    final replaced =
        name.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]+'), '_');
    final collapsed = replaced.replaceAll(RegExp(r'\s+'), ' ').trim();
    final stripped = collapsed.replaceAll(RegExp(r'^[. ]+|[. ]+$'), '');
    return stripped.isEmpty ? 'audio' : stripped;
  }
}
