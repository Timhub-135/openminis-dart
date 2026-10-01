#!/bin/sh
# Build the R2 guest rootfs squashfs inside Docker (arm64 container).
#
# Same output as tools/build-vm-rootfs.sh, but usable on an x86_64 host: the
# container runs as linux/arm64 so `apk --arch aarch64 --root` can execute the
# guest's own post-install scripts (busybox symlinks, ca-certificates triggers)
# without any cross emulation of the packages themselves.
#
# Requirements: docker with buildx, and QEMU binfmt registered when the host is
# not arm64 (`docker run --privileged --rm tonistiigi/binfmt --install arm64`,
# or docker/setup-qemu-action in CI).
#
#   ./tools/build-vm-rootfs-docker.sh [outdir]
set -eu

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$ROOT_DIR/.vm-payload-cache}"
mkdir -p "$OUT"

ALPINE_BRANCH="${ALPINE_BRANCH:-v3.22}"

# The guest userland list lives in build-vm-rootfs.sh; keep one source of truth.
PKGS=$(sed -n 's/^PKGS="\(.*\)"$/\1/p' "$ROOT_DIR/tools/build-vm-rootfs.sh")
if [ -z "$PKGS" ]; then
    echo "could not read PKGS from tools/build-vm-rootfs.sh" >&2
    exit 1
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/Dockerfile" <<EOF
FROM --platform=linux/arm64 alpine:3.22 AS builder
ARG ALPINE_BRANCH=${ALPINE_BRANCH}
RUN apk add --no-cache squashfs-tools
WORKDIR /work
COPY guest /work/guest
RUN mkdir -p /work/rootfs/etc/apk \\
 && printf '%s\n' "https://dl-cdn.alpinelinux.org/alpine/\${ALPINE_BRANCH}/main" \\
                   "https://dl-cdn.alpinelinux.org/alpine/\${ALPINE_BRANCH}/community" \\
      > /work/rootfs/etc/apk/repositories \\
 && apk --arch aarch64 --root /work/rootfs --initdb --keys-dir /etc/apk/keys \\
        --repositories-file /work/rootfs/etc/apk/repositories --no-cache -U add ${PKGS}
RUN for f in usr/local/bin/minis-agent etc/minis-rc etc/inittab etc/fstab; do \\
        install -D "/work/guest/\$f" "/work/rootfs/\$f"; \\
    done \\
 && chmod +x /work/rootfs/usr/local/bin/minis-agent /work/rootfs/etc/minis-rc \\
 && mkdir -p /work/rootfs/mnt/minis /work/rootfs/root /work/rootfs/tmp \\
 && chmod 1777 /work/rootfs/tmp \\
 && printf 'name=openminis-r2-vm\\nguest=alpine\${ALPINE_BRANCH#v}\\nbackend=qemu-system-aarch64-tcg\\nagent=minis-agent/1\\n' \\
      > /work/rootfs/etc/minis-vm-release \\
 && printf 'minis\\n' > /work/rootfs/etc/hostname \\
 && printf 'nameserver 10.0.2.3\\nnameserver 1.1.1.1\\n' > /work/rootfs/etc/resolv.conf
RUN mksquashfs /work/rootfs /work/alpine-minis.squashfs \\
      -comp zstd -Xcompression-level 19 -all-root -noappend -quiet

FROM scratch AS export
COPY --from=builder /work/alpine-minis.squashfs /alpine-minis.squashfs
EOF

cp -r "$ROOT_DIR/android/vm/guest" "$TMP/guest"

echo "==> docker buildx (arm64 container)"
docker buildx build --platform linux/arm64 \
    --output "type=local,dest=$TMP/out" \
    -f "$TMP/Dockerfile" "$TMP"

cp "$TMP/out/alpine-minis.squashfs" "$OUT/alpine-minis.squashfs"
DEST="$ROOT_DIR/android/app/src/main/assets/vm/alpine-minis.squashfs"
mkdir -p "$(dirname "$DEST")"
cp "$TMP/out/alpine-minis.squashfs" "$DEST"
ls -lh "$OUT/alpine-minis.squashfs"
echo "==> installed $DEST"
