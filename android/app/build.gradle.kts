plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.plamus"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    defaultConfig {
        applicationId = "com.example.plamus"
        // Floor of API 24 (Android 7.0) — comfortably below current Play
        // requirements and the minimum needed by `audio_service` /
        // `just_audio_background` for media-style notifications.
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")

            // R8 code shrinking and optimization.
            isMinifyEnabled = true

            // Remove unused resources (layouts, drawables, etc.).
            isShrinkResources = true

            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }

    // Exclude desktop binaries from Android assets at the Gradle level.
    // This prevents any accidentally committed .exe files from inflating
    // the APK, even if pubspec.yaml still declares assets/bin/.
    androidResources {
        ignoreAssetsPatterns += listOf("*.exe", "yt-dlp_*")
    }

    // ABI splitting is handled at the command line instead of here because
    // Flutter's gradle plugin injects ndk.abiFilters at build time, which
    // conflicts with splits.abi blocks.
    //
    // Use:  flutter build apk --split-per-abi
    // Or:   flutter build appbundle   (Play Store optimizes per-device)
}

flutter {
    source = "../.."
}
