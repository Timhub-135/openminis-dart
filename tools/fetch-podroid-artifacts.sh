#!/bin/sh
# Fetch the pieces of the R2 VM payload that are expensive to build (QEMU for
# Android arm64, a guest kernel, an initramfs) from the upstream Podroid release
# APK, and drop them where the OpenMinis Android build expects them.
#
#   ./tools/fetch-podroid-artifacts.sh [version]
#
# Upstream: https://github.com/ExTV/Podroid (GPLv2) — see NOTICE-vm-payload.md.
# The Alpine rootfs is *not* taken from there: tools/build-vm-rootfs.sh builds
# our own (with the minis-agent baked in) from the Alpine minirootfs.
set -eu

VER="${1:-v1.2.9}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/android/app/src/main"
APK_URL="https://github.com/ExTV/Podroid/releases/download/$VER/Podroid-$VER-release.apk"
WORK="$ROOT/.vm-payload-cache"
APK="$WORK/Podroid-$VER-release.apk"

mkdir -p "$WORK" "$APP/jniLibs/arm64-v8a" "$APP/assets/vm/qemu/keymaps"

if [ ! -f "$APK" ]; then
    echo "==> downloading $APK_URL"
    curl -L --http1.1 -C - -o "$APK" "$APK_URL"
fi
EXPECTED=$(curl -sIL "$APK_URL" | tr -d '\r' | awk 'tolower($1)=="content-length:"{n=$2} END{print n}')
ACTUAL=$(wc -c < "$APK" | tr -d ' ')
echo "==> apk $ACTUAL bytes (expected ${EXPECTED:-unknown})"
if [ -n "$EXPECTED" ] && [ "$ACTUAL" -lt "$EXPECTED" ]; then
    echo "!! download incomplete — re-run this script to resume" >&2
    exit 1
fi

UNPACK="$WORK/unpacked-$VER"
if [ ! -d "$UNPACK/lib" ]; then
    echo "==> unpacking"
    rm -rf "$UNPACK"
    mkdir -p "$UNPACK"
    unzip -o -q "$APK" -d "$UNPACK"
fi

echo "==> native libraries (executables live here, not in app data)"
cp "$UNPACK/lib/arm64-v8a/libqemu-system-aarch64.so" "$APP/jniLibs/arm64-v8a/"
cp "$UNPACK/lib/arm64-v8a/libslirp.so"               "$APP/jniLibs/arm64-v8a/"
cp "$UNPACK/lib/arm64-v8a/libpodroid-launcher.so"    "$APP/jniLibs/arm64-v8a/"

echo "==> guest kernel + initramfs + QEMU data files"
cp "$UNPACK/assets/vmlinuz-virt" "$APP/assets/vm/"
cp "$UNPACK/assets/initrd.img"   "$APP/assets/vm/"
cp "$UNPACK/assets/qemu/efi-virtio.rom" "$APP/assets/vm/qemu/"
cp -r "$UNPACK/assets/qemu/keymaps/." "$APP/assets/vm/qemu/keymaps/"

echo "==> verifying 16 KB page alignment (Android 15+ devices)"
python3 - "$APP/jniLibs/arm64-v8a" <<'PY'
import glob, struct, sys
bad = 0
for path in sorted(glob.glob(sys.argv[1] + '/*.so')):
    data = open(path, 'rb').read()
    if data[:4] != b'\x7fELF':
        print(f'  {path}: not an ELF — refusing'); bad += 1; continue
    phoff = struct.unpack_from('<Q', data, 32)[0]
    phes = struct.unpack_from('<H', data, 54)[0]
    phn = struct.unpack_from('<H', data, 56)[0]
    aligns = [struct.unpack_from('<Q', data, phoff + i * phes + 48)[0]
              for i in range(phn)
              if struct.unpack_from('<I', data, phoff + i * phes)[0] == 1]
    ok = min(aligns) >= 16384 if aligns else False
    print(f'  {path.split("/")[-1]}: min_align={min(aligns) if aligns else 0} {"OK" if ok else "FAIL"}')
    bad += 0 if ok else 1
sys.exit(1 if bad else 0)
PY

echo "==> done. rootfs is separate: tools/build-vm-rootfs.sh"
