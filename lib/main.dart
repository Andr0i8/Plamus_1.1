import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:window_manager/window_manager.dart';

import 'database/database_helper.dart';
import 'services/audio_player_service.dart';
import 'services/binary_service.dart';
import 'services/library_service.dart';
import 'theme/app_theme.dart';
import 'ui/shell/plamus_shell.dart';
import 'ui/shell/plamus_shell_mobile.dart';
import 'ui/theme/theme_controller.dart';

/// Application entry: Cross-platform music player (Desktop + Mobile).
///
/// **Desktop audio:** `just_audio` requires media_kit backend on Windows/Linux.
/// **Mobile audio:** `just_audio_background` for background playback.
/// After changing audio dependencies, do a full cold restart.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Mobile: Lock to portrait mode.
  // Note: JustAudioBackground.init and permission requests are deferred to
  // _PlamusAppState.initState via a postFrameCallback because they require
  // the Android Activity to exist, which isn't true this early in main().
  if (Platform.isAndroid || Platform.isIOS) {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  }

  // Desktop: Initialize window manager for fullscreen support
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    await windowManager.ensureInitialized();

    const windowOptions = WindowOptions(
      minimumSize: Size(800, 600),
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.normal,
    );

    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  // Desktop: media_kit backend required for just_audio.
  if (Platform.isWindows) {
    JustAudioMediaKit.ensureInitialized(
      windows: true,
      linux: false,
    );
    JustAudioMediaKit.title = 'Plamus';
    // Note: media_kit handles caching internally for local files
    // The "Failed to create file cache" warning can be safely ignored for local playback
  }

  // Desktop: SQLite via FFI.
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  // Desktop only: extract yt-dlp/ffmpeg binaries.
  // On Android/iOS, downloads use AudioDownloadService (pure Dart) instead.
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    await BinaryService.instance.ensureBinariesExtracted();
  }

  // Initialize audio service
  final audio = AudioPlayerService();
  await audio.init();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => LibraryService(DatabaseHelper.instance),
        ),
        ChangeNotifierProvider.value(value: audio),
        ChangeNotifierProvider(create: (_) => ThemeController()),
      ],
      child: const PlamusApp(),
    ),
  );
}

/// Request storage permissions for mobile.
Future<void> _requestMobilePermissions() async {
  if (Platform.isAndroid) {
    // Request storage permissions
    await Permission.storage.request();
    await Permission.audio.request();

    // Android 13+ requires notification permission
    if (await Permission.notification.isDenied) {
      await Permission.notification.request();
    }
  }
}

/// Root [MaterialApp] wired to [ThemeController] and Plamus themes.
class PlamusApp extends StatefulWidget {
  /// Creates the root widget.
  const PlamusApp({super.key});

  @override
  State<PlamusApp> createState() => _PlamusAppState();
}

class _PlamusAppState extends State<PlamusApp> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (Platform.isAndroid || Platform.isIOS) {
        await JustAudioBackground.init(
          androidNotificationChannelId: 'com.plamus.audio',
          androidNotificationChannelName: 'Plamus Audio',
          androidNotificationOngoing: true,
          androidShowNotificationBadge: true,
        );
        await _requestMobilePermissions();
      }
    });
  }

  Future<void> _handleF11() async {
    if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) return;

    try {
      final isFullScreen = await windowManager.isFullScreen();
      if (isFullScreen) {
        await windowManager.setFullScreen(false);
      } else {
        await windowManager.setFullScreen(true);
      }
    } catch (e) {
      debugPrint('F11 fullscreen toggle failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeCtrl = context.watch<ThemeController>();

    return Shortcuts(
      shortcuts: <LogicalKeySet, Intent>{
        LogicalKeySet(LogicalKeyboardKey.f11): const _FullscreenIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _FullscreenIntent: CallbackAction<_FullscreenIntent>(
            onInvoke: (_) {
              _handleF11();
              return null;
            },
          ),
        },
        child: MaterialApp(
          title: 'Plamus',
          debugShowCheckedModeBanner: false,
          theme: PlamusTheme.light(accentColor: themeCtrl.accentColor),
          darkTheme: PlamusTheme.dark(accentColor: themeCtrl.accentColor),
          themeMode: themeCtrl.mode,
          home: Platform.isAndroid || Platform.isIOS
              ? const PlamusShellMobile()
              : const PlamusShell(),
        ),
      ),
    );
  }
}

/// Intent for F11 fullscreen toggle.
class _FullscreenIntent extends Intent {
  const _FullscreenIntent();
}
