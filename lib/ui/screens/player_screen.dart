import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/repeat_mode.dart' as plamus;
import '../../models/track_model.dart';
import '../../services/audio_player_service.dart';
import '../widgets/sleep_timer_button.dart';

/// Full-screen player for mobile with complete media controls.
class PlayerScreen extends StatelessWidget {
  const PlayerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final audioService = context.watch<AudioPlayerService>();
    final accentColor = Theme.of(context).colorScheme.primary;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Now Playing'),
        centerTitle: true,
        actions: const [
          SleepTimerButton(
            iconSize: 24,
            padding: EdgeInsets.symmetric(horizontal: 8),
          ),
        ],
      ),
      body: StreamBuilder<TrackModel?>(
        stream: audioService.currentTrackStream,
        builder: (context, trackSnapshot) {
          final track = trackSnapshot.data;

          if (track == null) {
            return const Center(child: Text('No track playing'));
          }

          return Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Album art
                Container(
                  width: 280,
                  height: 280,
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    Icons.music_note,
                    size: 120,
                    color: accentColor,
                  ),
                ),

                const SizedBox(height: 40),

                // Track title - REACTIVE
                Text(
                  track.title,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),

                const SizedBox(height: 8),

                // Artist - REACTIVE
                Text(
                  track.displayArtistLabel,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.6),
                      ),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 40),

                // Progress slider
                StreamBuilder<Duration>(
                  stream: audioService.positionStream,
                  builder: (context, posSnapshot) {
                    return StreamBuilder<Duration?>(
                      stream: audioService.durationStream,
                      builder: (context, durSnapshot) {
                        final position = posSnapshot.data ?? Duration.zero;
                        final duration = durSnapshot.data ?? Duration.zero;
                        final progress = duration.inMilliseconds > 0
                            ? position.inMilliseconds / duration.inMilliseconds
                            : 0.0;

                        return Column(
                          children: [
                            SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                activeTrackColor: accentColor,
                                thumbColor: accentColor,
                                inactiveTrackColor:
                                    accentColor.withValues(alpha: 0.3),
                              ),
                              child: Slider(
                                value: progress.clamp(0.0, 1.0),
                                onChanged: (value) {
                                  final newPos = Duration(
                                    milliseconds:
                                        (value * duration.inMilliseconds)
                                            .round(),
                                  );
                                  audioService.seek(newPos);
                                },
                              ),
                            ),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(_formatDuration(position)),
                                  Text(_formatDuration(duration)),
                                ],
                              ),
                            ),
                          ],
                        );
                      },
                    );
                  },
                ),

                const SizedBox(height: 24),

                // Volume slider
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Icon(
                        Icons.volume_down,
                        color: accentColor,
                        size: 24,
                      ),
                      Expanded(
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            activeTrackColor: accentColor,
                            thumbColor: accentColor,
                            inactiveTrackColor:
                                accentColor.withValues(alpha: 0.3),
                          ),
                          child: Slider(
                            value: audioService.volume,
                            onChanged: (value) {
                              audioService.setVolumeLinear(value);
                            },
                          ),
                        ),
                      ),
                      Icon(
                        Icons.volume_up,
                        color: accentColor,
                        size: 24,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Playback controls
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Repeat button with 3-state logic
                    SizedBox(
                      width: 48,
                      height: 48,
                      child: IconButton(
                        icon: _buildRepeatIcon(
                            audioService.repeatMode, accentColor),
                        iconSize: 28,
                        color: audioService.repeatMode != plamus.RepeatMode.off
                            ? accentColor
                            : Colors.grey,
                        onPressed: () => audioService.cycleRepeatMode(),
                      ),
                    ),

                    const SizedBox(width: 16),

                    // Previous button
                    SizedBox(
                      width: 48,
                      height: 48,
                      child: IconButton(
                        icon: const Icon(Icons.skip_previous),
                        iconSize: 40,
                        color: accentColor,
                        onPressed: () => audioService.skipPrevious(),
                      ),
                    ),

                    const SizedBox(width: 16),

                    // Play/Pause button
                    StreamBuilder<bool>(
                      stream: audioService.playingStream,
                      builder: (context, snapshot) {
                        final isPlaying = snapshot.data ?? false;
                        return Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            color: accentColor,
                            shape: BoxShape.circle,
                          ),
                          child: IconButton(
                            icon: Icon(
                              isPlaying ? Icons.pause : Icons.play_arrow,
                              size: 40,
                            ),
                            color: Theme.of(context).colorScheme.onPrimary,
                            onPressed: () {
                              if (isPlaying) {
                                audioService.pause();
                              } else {
                                audioService.play();
                              }
                            },
                          ),
                        );
                      },
                    ),

                    const SizedBox(width: 16),

                    // Next button
                    SizedBox(
                      width: 48,
                      height: 48,
                      child: IconButton(
                        icon: const Icon(Icons.skip_next),
                        iconSize: 40,
                        color: accentColor,
                        onPressed: () => audioService.skipNext(),
                      ),
                    ),

                    const SizedBox(width: 16),

                    // Shuffle button — tints to the accent color when
                    // active so the user can see at a glance whether the
                    // queue order is being randomized (BUG 3).
                    SizedBox(
                      width: 48,
                      height: 48,
                      child: IconButton(
                        tooltip: audioService.shuffleEnabled
                            ? 'Shuffle: ON'
                            : 'Shuffle: OFF',
                        icon: const Icon(Icons.shuffle),
                        iconSize: 28,
                        color: audioService.shuffleEnabled
                            ? accentColor
                            : Colors.grey,
                        onPressed: () => audioService.toggleShuffle(),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Builds repeat icon with badge for "one" mode
  Widget _buildRepeatIcon(plamus.RepeatMode mode, Color accentColor) {
    if (mode == plamus.RepeatMode.one) {
      return Stack(
        alignment: Alignment.center,
        children: [
          Icon(Icons.repeat, color: accentColor),
          Positioned(
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: accentColor,
                shape: BoxShape.circle,
              ),
              child: const Text(
                '1',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      );
    }
    return Icon(
      Icons.repeat,
      color: mode == plamus.RepeatMode.all ? accentColor : Colors.grey,
    );
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}
