#!/bin/sh
# Build the APK inside the Minis Android sandbox (Alpine aarch64 / PRoot).
#
# Why this exists: Flutter's official Linux SDK ships x86_64 only, but the
# toolchain bootstraps an *arm64* Dart SDK when asked to, so the whole build can
# run natively on an aarch64 phone — provided the storage mirrors are set (the
# default hosts time out from here).
#
# One-time environment setup this script assumes:
#   /opt/flutter                 Flutter 3.47.5 (arm64 cache bootstrapped)
#   /opt/android-sdk             cmdline-tools 11076708 + platform 36 + build-tools 36
#   /opt/gradle-home             Gradle 9.3.1 pre-seeded into wrapper/dists
#   /opt/pubcache                pub cache
#
# Usage: sh tools/build-apk-sandbox.sh [--release]
set -eu

MODE="--debug"
[ "${1:-}" = "--release" ] && MODE="--release"

export PATH=/opt/flutter/bin:/opt/android-sdk/cmdline-tools/latest/bin:/opt/android-sdk/platform-tools:$PATH
export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
export PUB_HOSTED_URL=https://pub.flutter-io.cn
export PUB_CACHE=/opt/pubcache
export ANDROID_HOME=/opt/android-sdk
export ANDROID_SDK_ROOT=/opt/android-sdk
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk
export GRADLE_USER_HOME=/opt/gradle-home
unset HTTP_PROXY HTTPS_PROXY http_proxy https_proxy

cd "$(dirname "$0")/.."
printf 'flutter.sdk=/opt/flutter\nsdk.dir=/opt/android-sdk\n' > android/local.properties

flutter pub get
flutter build apk "$MODE"
ls -lh build/app/outputs/flutter-apk/ 2>/dev/null || true
