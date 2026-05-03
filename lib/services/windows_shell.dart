import 'dart:io';

/// Cross-platform shell helpers (reveal file in system file manager).
class WindowsShell {
  WindowsShell._();

  /// Opens system file manager with the file pre-selected.
  ///
  /// - Windows: Opens Explorer with file selected
  /// - macOS/Linux: Could use 'open' or 'xdg-open' if needed
  ///
  /// Throws if [filePath] is empty or the file does not exist.
  static Future<void> showInFolder(String filePath) async {
    if (Platform.isWindows) {
      final normalized = filePath.replaceAll('/', '\\');
      final f = File(normalized);
      if (!await f.exists()) {
        throw FileSystemException('Cannot show missing file in folder', filePath);
      }
      final explorerArgs = <String>['/select,${f.path}'];
      final result = await Process.run('explorer', explorerArgs);
      if (result.exitCode != 0) {
        throw ProcessException(
          'explorer',
          explorerArgs,
          result.stderr.toString().trim(),
          result.exitCode,
        );
      }
    }
    // macOS/Linux could use 'open' or 'xdg-open' here if needed.
  }
}
