package com.example.plamus

import com.ryanheise.audioservice.AudioServiceFragmentActivity

// AudioServiceFragmentActivity is itself a subclass of
// io.flutter.embedding.android.FlutterFragmentActivity. It additionally
// overrides provideFlutterEngine / getCachedEngineId so the activity binds
// to the shared "audio_service_engine" FlutterEngine that the audio_service
// plugin caches. Extending plain FlutterFragmentActivity creates a separate
// engine, which makes audio_service throw
// "The Activity class declared in your AndroidManifest.xml is wrong or has
// not provided the correct FlutterEngine" when JustAudioBackground.init runs.
class MainActivity : AudioServiceFragmentActivity()
