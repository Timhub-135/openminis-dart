plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin
    // Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.openminis.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.openminis.app"
        // Flutter's min SDK; the agent + sync work fine from there. The R2 VM
        // only needs API 21+ of the host (QEMU runs entirely in userspace).
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // The R2 VM payload is aarch64 only: QEMU, the guest kernel and the
        // Alpine rootfs are all arm64-v8a. Shipping 32-bit ABI stubs would only
        // bloat the APK, so the native libraries are arm64-only.
        ndk {
            abiFilters += "arm64-v8a"
        }
    }

    // The sandbox exec()s QEMU out of the APK's native library directory, since
    // Android denies exec() on files inside the app's writable data dir for
    // targetSdk >= 29 (W^X). That requires the libraries to be *extracted* at
    // install time rather than mapped straight out of the APK, which is what
    // useLegacyPackaging turns back on.
    //
    // The VM images under assets/vm need no special handling: VmAssetInstaller
    // copies them into filesDir on first launch, so whether aapt deflates them
    // inside the APK only affects download size.
    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
    }

    buildTypes {
        release {
            // Debug keys so `flutter run --release` and CI builds work out of
            // the box; configure a real keystore before publishing.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
