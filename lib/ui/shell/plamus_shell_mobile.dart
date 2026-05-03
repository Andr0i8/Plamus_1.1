import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/audio_player_service.dart';
import '../screens/history_screen.dart';
import '../screens/home_library_screen.dart';
import '../screens/liked_screen.dart';
import '../screens/settings_screen.dart';
import '../widgets/mobile_mini_player.dart';

/// Mobile UI shell with bottom navigation and mini-player.
class PlamusShellMobile extends StatefulWidget {
  const PlamusShellMobile({super.key});

  @override
  State<PlamusShellMobile> createState() => _PlamusShellMobileState();
}

class _PlamusShellMobileState extends State<PlamusShellMobile> {
  int _currentIndex = 0;

  final List<Widget> _screens = [
    const HomeLibraryScreen(),
    const LikedScreen(),
    const HistoryScreen(),
    const SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final audioService = context.watch<AudioPlayerService>();
    final hasTrack = audioService.currentTrack != null;

    return Scaffold(
      body: SafeArea(
        child: IndexedStack(
          index: _currentIndex,
          children: _screens,
        ),
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Mini-player (70px fixed height)
          if (hasTrack) const MobileMiniPlayer(),

          // Bottom navigation
          BottomNavigationBar(
            currentIndex: _currentIndex,
            onTap: (index) => setState(() => _currentIndex = index),
            type: BottomNavigationBarType.fixed,
            selectedItemColor: Theme.of(context).colorScheme.primary,
            unselectedItemColor: Colors.grey,
            items: const [
              BottomNavigationBarItem(
                icon: Icon(Icons.library_music),
                label: 'Library',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.favorite),
                label: 'Liked',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.history),
                label: 'History',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.settings),
                label: 'Settings',
              ),
            ],
          ),
        ],
      ),
    );
  }
}
