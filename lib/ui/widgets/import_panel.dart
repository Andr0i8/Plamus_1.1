import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/audio_download_service.dart';
import '../../services/binary_service.dart';
import '../../services/download_service.dart';
import '../../services/library_service.dart';
import '../../services/media_ingest_service.dart';
import '../../services/plamus_paths.dart';

/// Shared import UI: URL field, pick files, drag-and-drop (desktop), and progress.
///
/// Validation behavior (BUG 4 / BUG 5):
///   * Empty / non-http(s) URLs are rejected inline with a red field error
///     instead of a snackbar.
///   * On Android / iOS, only YouTube links are accepted. Anything else
///     would be routed through our YouTube-only Railway extractor or the
///     plain-HTTP fallback that produces broken files for sites like VK,
///     so we tell the user up-front rather than letting the download
///     fail later.
///
/// Library / playlist mode (BUG 6):
///   * [addToLibrary] = `true` (default) → imported tracks appear in the
///     main library list. Used by the global Search / Import flow.
///   * [addToLibrary] = `false` → imported tracks are saved with
///     `inLibrary = 0` and are only reachable through whichever playlist
///     the caller subsequently links them to via [onTrackImported].
///
/// [onTrackImported] is invoked with the new track's id after every
/// successful import so callers can wire it into a playlist if needed.
class ImportPanel extends StatefulWidget {
  /// Creates the import panel.
  const ImportPanel({
    super.key,
    this.onDone,
    this.onTrackImported,
    this.addToLibrary = true,
  });

  /// Called once after every successful import (URL or file).
  final VoidCallback? onDone;

  /// Called with the new track's id after every successful import. Used
  /// by playlist-detail's "Import new track" flow to link the new row
  /// into the playlist via `addTrackToPlaylist`.
  final ValueChanged<int>? onTrackImported;

  /// Whether to surface imported tracks in the main library. See class
  /// docs.
  final bool addToLibrary;

  @override
  State<ImportPanel> createState() => _ImportPanelState();
}

class _ImportPanelState extends State<ImportPanel> {
  final _urlCtrl = TextEditingController();
  bool _busy = false;
  double _progress = 0;
  String _status = '';

  /// Inline error displayed via the URL field's `errorText` (red border +
  /// red helper line). Replaces the previous pink error snackbar.
  String? _errorMessage;

  @override
  void dispose() {
    _urlCtrl.dispose();
    super.dispose();
  }

  Future<void> _setBusy(
    bool v, {
    double p = 0,
    String msg = '',
    String? error,
  }) async {
    if (!mounted) return;
    setState(() {
      _busy = v;
      _progress = p;
      _status = msg;
      _errorMessage = error;
    });
  }

  /// Validates [url] for the active platform and returns an inline error
  /// message, or `null` when the URL passes all checks.
  String? _validateUrlForCurrentPlatform(String url) {
    if (url.isEmpty) {
      return 'Please paste a link first.';
    }
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      return 'Please add https:// at the start of the URL';
    }
    final isMobile = Platform.isAndroid || Platform.isIOS;
    if (isMobile && !AudioDownloadService.isYouTubeUrl(url)) {
      // The mobile extractor server only handles YouTube; anything else
      // either gets a broken HTML body back (VK, SoundCloud pages) or is
      // outside the scope of what we ship today. Fail fast (BUG 5).
      return 'Only YouTube links are supported';
    }
    return null;
  }

  /// Imports a local path (file picker or drop).
  Future<void> _ingestPath(String path) async {
    final lib = context.read<LibraryService>();
    await _setBusy(true, p: 0.05, msg: 'Importing\u2026', error: null);
    try {
      final root = await PlamusPaths.musicLibraryDirectory();
      final id = await MediaIngestService.ingestAndRegister(
        sourcePath: path,
        libraryDirectory: root,
        inLibrary: widget.addToLibrary,
        onLog: (m) {
          if (!mounted) return;
          setState(() => _status = m);
        },
      );
      await lib.refreshAll();
      widget.onTrackImported?.call(id);
      widget.onDone?.call();
      await _setBusy(false, msg: 'Done.');
    } catch (e) {
      await _setBusy(false, error: 'Import failed: $e');
    }
  }

  /// Downloads a remote URL.
  ///
  /// Mobile (Android/iOS): unified [AudioDownloadService]. YouTube URLs are
  /// forwarded to a remote extraction server (see `YoutubeDownloadService`);
  /// the server may include `X-Track-Title` / `X-Track-Artist` headers
  /// which we propagate to [LibraryService.registerTrackFile] so the row
  /// is created with the real channel name (BUG 2).
  ///
  /// Desktop (Windows/Linux/macOS): yt-dlp binary via [DownloadService] for
  /// broad site support and proper MP3 transcoding.
  Future<void> _downloadUrl() async {
    final url = _urlCtrl.text.trim();

    final validationError = _validateUrlForCurrentPlatform(url);
    if (validationError != null) {
      await _setBusy(false, error: validationError);
      return;
    }

    final lib = context.read<LibraryService>();
    await _setBusy(true, p: 0, msg: 'Starting download\u2026', error: null);

    try {
      final root = await PlamusPaths.musicLibraryDirectory();
      String outputPath;
      String? remoteTitle;
      String? remoteArtist;

      if (Platform.isAndroid || Platform.isIOS) {
        // Mobile: pure-Dart audio download (YouTube) with metadata.
        final result =
            await AudioDownloadService.instance.downloadAudioWithMetadata(
          url: url,
          outputDirectory: root,
          onProgress: (p) {
            if (!mounted) return;
            setState(() {
              _progress = p;
              _status = 'Downloading\u2026 ${(p * 100).toStringAsFixed(0)}%';
              _errorMessage = null;
            });
          },
          onLog: (msg) {
            if (!mounted) return;
            setState(() => _status = msg);
          },
        );
        outputPath = result.filePath;
        remoteTitle = result.title;
        remoteArtist = result.artist;
      } else {
        // Desktop: yt-dlp binary supports many sites natively, so we don't
        // restrict to YouTube here. Title / artist tagging from yt-dlp is
        // out of scope for this fix — the row falls back to filename /
        // "Unknown" exactly like before.
        final bin = BinaryService.instance.lastResolution;
        if (bin == null || !bin.ytDlpAvailable) {
          final detail = bin != null
              ? bin.errors.join(' ')
              : 'Binary resolution did not run.';
          await _setBusy(false, error: 'yt-dlp is not available. $detail');
          return;
        }

        outputPath = await DownloadService.downloadUrlToMp3(
          url: url,
          outputDirectory: root,
          ytDlpExecutablePath: bin.ytDlpPath,
          onProgress: (p) {
            if (!mounted) return;
            setState(() {
              _progress = p.fraction;
              _status = p.message;
              _errorMessage = null;
            });
          },
        );
      }

      final id = await lib.registerTrackFile(
        outputPath,
        artist: remoteArtist,
        title: remoteTitle,
        inLibrary: widget.addToLibrary,
      );
      await lib.refreshAll();
      widget.onTrackImported?.call(id);
      _urlCtrl.clear();
      widget.onDone?.call();
      await _setBusy(false, p: 1, msg: 'Download complete.', error: null);
    } catch (_) {
      // Map opaque server / network errors to a single friendly inline
      // message — the previous version surfaced raw exception text in a
      // pink snackbar (BUG 4).
      await _setBusy(false, error: 'Invalid or unsupported URL');
    }
  }

  Future<void> _pickFiles() async {
    final res = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (res == null || res.files.isEmpty) return;
    for (final f in res.files) {
      final path = f.path ?? '';
      if (path.isEmpty) continue;
      await _ingestPath(path);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isMobile = Platform.isAndroid || Platform.isIOS;

    // Only show binary errors on desktop where they matter.
    final bin = isMobile ? null : BinaryService.instance.lastResolution;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (bin != null && bin.errors.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Material(
              color: theme.colorScheme.errorContainer.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  bin.errors.join('\n'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onErrorContainer,
                  ),
                ),
              ),
            ),
          ),
        TextField(
          controller: _urlCtrl,
          decoration: InputDecoration(
            labelText: 'Media link',
            hintText: isMobile
                ? 'Paste YouTube link'
                : 'Paste YouTube, web audio, or video URL',
            border: const OutlineInputBorder(),
            // The TextField's own errorText drives the red border + the
            // red helper line below the field, replacing the old snackbar.
            errorText: _errorMessage,
          ),
          onChanged: (_) {
            // Clear stale error as the user types so the red state doesn't
            // linger after they fix the URL.
            if (_errorMessage != null) {
              setState(() => _errorMessage = null);
            }
          },
          onSubmitted: (_) => _downloadUrl(),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            FilledButton.icon(
              onPressed: _busy ? null : _downloadUrl,
              icon: const Icon(Icons.download),
              label: const Text('Download audio'),
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : _pickFiles,
              icon: const Icon(Icons.folder_open),
              label: const Text('Browse files'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        // Drag-and-drop (desktop only — DropTarget requires desktop_drop)
        if (!isMobile)
          SizedBox(
            height: 220,
            child: DropTarget(
              onDragDone: (detail) async {
                if (_busy) return;
                for (final f in detail.files) {
                  final path = f.path;
                  if (path.isEmpty) continue;
                  await _ingestPath(path);
                }
              },
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: theme.dividerColor.withValues(alpha: 0.4),
                  ),
                ),
                child: Center(
                  child: Text(
                    'Drag and drop audio or video files here',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.textTheme.bodyLarge?.color
                          ?.withValues(alpha: 0.75),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          ),
        if (_busy || _status.isNotEmpty) ...[
          const SizedBox(height: 12),
          if (_busy) LinearProgressIndicator(value: _progress == 0 ? null : _progress),
          if (_status.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _status,
                style: theme.textTheme.bodySmall,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ],
    );
  }
}
