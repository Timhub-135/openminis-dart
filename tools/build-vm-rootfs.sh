#!/bin/sh
# Build the R2 guest rootfs: Alpine aarch64 + the minis-agent console daemon,
# packed read-only as squashfs for the APK (android/app/src/main/assets/vm).
#
#   ./tools/build-vm-rootfs.sh [outdir]
#
# Must run on an aarch64 Linux host with apk-tools (Alpine, or the Minis
# sandbox): the guest packages are the *native* arch there, so no cross
# emulation is involved. mksquashfs (squashfs-tools) is required as well.
#
# The guest files live in android/vm/guest/ (also validated by the Dart test
# suite, which shell-checks them):
#   usr/local/bin/minis-agent   console command endpoint (the MINIS_* protocol)
#   etc/minis-rc                sysinit: mounts, 9p share, slirp networking
#   etc/inittab                 busybox init table (no login, no getty)
#   etc/fstab
set -eu

ALPINE_BRANCH="${ALPINE_BRANCH:-v3.22}"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
GUEST="$ROOT_DIR/android/vm/guest"
OUT="${1:-$ROOT_DIR/.vm-payload-cache}"

# Guest userland. Deliberately a general-purpose dev box: the agent's whole
# point is that the model can install more (`apk add …`) and have it persist in
# the writable overlay. Keep this list lean enough that the squashfs stays
# ~45 MB; anything heavier is one `apk add` away at runtime.
PKGS="alpine-base alpine-baselayout busybox openrc \
bash coreutils findutils grep sed gawk \
tar gzip xz zstd bzip2 unzip \
curl wget ca-certificates openssl \
git python3 py3-pip \
procps less nano vim util-linux e2fsprogs \
iproute2 iputils bind-tools tzdata shadow"

WORK="$(mktemp -d)"
ROOT="$WORK/rootfs"
trap 'rm -rf "$WORK"' EXIT

echo "==> staging $ROOT"
mkdir -p "$ROOT/etc/apk" "$OUT"
printf '%s\n' \
  "https://dl-cdn.alpinelinux.org/alpine/${ALPINE_BRANCH}/main" \
  "https://dl-cdn.alpinelinux.org/alpine/${ALPINE_BRANCH}/community" \
  > "$ROOT/etc/apk/repositories"

echo "==> apk add (arch=aarch64)"
apk --arch aarch64 --root "$ROOT" --initdb \
    --keys-dir /etc/apk/keys \
    --repositories-file "$ROOT/etc/apk/repositories" \
    --no-cache -U add $PKGS 2>&1 | tail -3

echo "==> guest files"
for f in usr/local/bin/minis-agent etc/minis-rc etc/inittab etc/fstab; do
    install -D "$GUEST/$f" "$ROOT/$f"
done
chmod +x "$ROOT/usr/local/bin/minis-agent" "$ROOT/etc/minis-rc"
mkdir -p "$ROOT/mnt/minis" "$ROOT/root" "$ROOT/tmp" "$ROOT/proc" "$ROOT/sys" "$ROOT/dev"
chmod 1777 "$ROOT/tmp"

cat > "$ROOT/etc/minis-vm-release" <<EOF
name=openminis-r2-vm
guest=alpine${ALPINE_BRANCH#v}
backend=qemu-system-aarch64-tcg
agent=minis-agent/1
EOF
printf 'minis\n' > "$ROOT/etc/hostname"
printf 'nameserver 10.0.2.3\nnameserver 1.1.1.1\n' > "$ROOT/etc/resolv.conf"

echo "==> mksquashfs"
SQUASH="$OUT/alpine-minis.squashfs"
rm -f "$SQUASH"
mksquashfs "$ROOT" "$SQUASH" -comp zstd -Xcompression-level 19 -all-root -noappend -quiet >/dev/null
ls -lh "$SQUASH"

DEST="$ROOT_DIR/android/app/src/main/assets/vm/alpine-minis.squashfs"
mkdir -p "$(dirname "$DEST")"
cp "$SQUASH" "$DEST"
echo "==> installed $DEST"
