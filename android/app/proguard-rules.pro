# Plamus ProGuard / R8 rules
# ============================================================================

# Flutter defaults — keep the Flutter engine and plugins intact.
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# just_audio / audio_service background playback.
-keep class com.ryanheise.audioservice.** { *; }
-keep class com.google.android.exoplayer2.** { *; }
-keep class androidx.media.** { *; }

# Keep SQLite native bindings (sqflite).
-keep class org.sqlite.** { *; }
-keep class io.flutter.plugins.sqflite.** { *; }

# Suppress warnings for optional/reflection-based code in dependencies.
-dontwarn com.google.android.play.core.**
-dontwarn io.flutter.embedding.engine.deferredcomponents.**

# Standard optimizations.
-optimizationpasses 5
-allowaccessmodification
-dontusemixedcaseclassnames
