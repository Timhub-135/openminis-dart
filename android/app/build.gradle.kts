plugins {
    id "com.android.application"
    id "kotlin-android"
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin
    // Gradle plugins.
    id "dev.flutter.flutter-gradle-plugin"
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
        // Flutter min SDK is API 21; agents/sync work fine from there.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutterVersionCode.toInteger()
        versionName = flutterVersionName

        // The R2 VM payload (QEMU + kernel + squashfs) is arm64-only.
        ndk {
            abiFilters += "arm64-v8a"
        }
    }

    // The sandbox executes QEMU out of the APK's native library dir, because
    // Android (API 29+) denies exec() on files in the app's writable data dir.
    // That only works when the libs are extracted at install time instead of
    // being mapped straight out of the APK — hence useLegacyPackaging.
    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
        resources {
            // The VM blobs are already-compressed images (squashfs, gzipped
            // initramfs): re-deflating them costs build time and APK memory for
            // no gain, and QEMU reads them from disk anyway.
            noCompress += listOf("squashfs", "img", "rom", "vmlinuz-virt")
        }
    }

    buildTypes {
        release {
            // Use the Flutter default signing for dev builds; configure a
            // real keystore before shipping.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

// Kotlin 2.x moved the JVM target out of `kotlinOptions` (removed in AGP 9), so
// the target is declared through the Kotlin extension instead.
kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
