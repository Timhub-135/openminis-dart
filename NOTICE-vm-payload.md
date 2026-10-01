# Third-party payload shipped in the Android APK (R2 VM backend)

The Android sandbox boots a Linux VM. Its executables and images are third-party
software; this file records what is shipped, where it came from, and under which
licence, so that whoever distributes the APK can meet the obligations.

## What is bundled, and where

| Artifact | Path in APK | Origin | Licence |
|---|---|---|---|
| `libqemu-system-aarch64.so` | `lib/arm64-v8a/` | QEMU (system emulator, TCG), cross-built for `aarch64-linux-android` by the [Podroid](https://github.com/ExTV/Podroid) project (`Dockerfile`, `podroidQemuVersion`) | GPLv2 |
| `libslirp.so` | `lib/arm64-v8a/` | libslirp (user-mode networking for QEMU) | BSD-3-Clause |
| `libpodroid-launcher.so` | `lib/arm64-v8a/` | `podroid-launcher.c` from Podroid — a ~50-line wrapper that calls `prctl(PR_SET_PDEATHSIG, SIGKILL)` before `execv`-ing QEMU | GPLv2 |
| `vmlinuz-virt` | `assets/vm/` | Linux kernel built by Podroid from its published `podroid_kernel.config` | GPLv2 |
| `initrd.img` | `assets/vm/` | Podroid's initramfs (busybox + e2fsprogs + overlay/switch_root init) | GPLv2 (busybox, e2fsprogs) |
| `qemu/efi-virtio.rom`, `qemu/keymaps/*` | `assets/vm/` | QEMU data files | GPLv2 (QEMU), keymaps under their upstream terms |
| `alpine-minis.squashfs` | `assets/vm/` | **Built by this repo** (`tools/build-vm-rootfs.sh`) from the official Alpine `minirootfs` tarball plus our own `minis-agent`; package list is in that script | Per-package (Alpine: mostly MIT / BSD / GPL / Apache) |

`tools/fetch-podroid-artifacts.sh` re-creates the Podroid-derived rows from a
pinned upstream release; nothing is taken from an unpinned build.

## Why this is "mere aggregation", and why that is not the whole story

The app does not link against QEMU or the kernel — it spawns QEMU as a separate
process and boots a kernel image, so the Flutter/Dart application is not a
derivative work of them (standard launcher/OS boundary). That is what makes
shipping a GPLv2 emulator inside an APK normal practice.

The GPLv2 obligations still land on the *distributor of the binary*:

1. **Source.** QEMU and the kernel are redistributed binaries here, so their
   complete corresponding source must be available. The upstream Podroid
   repository publishes both build recipes (`Dockerfile`, `podroid_kernel.config`)
   and is itself the source of these exact binaries; point users there, and keep
   the exact version pinned in `tools/fetch-podroid-artifacts.sh`.
2. **Notices and licence text.** Keep this file and the upstream licence text
   with the distribution, and do not remove copyright notices from the payload.
3. **No additional restrictions.** If you distribute the APK with terms that
   forbid what GPLv2 permits for these components, those terms cannot apply to
   the bundled GPLv2 parts.

If you would rather not redistribute GPLv2 code at all, the two alternatives are
(a) ship no VM payload and let the user install one, or (b) build QEMU and the
kernel yourself from source under the same licences — which changes nothing
about the obligations, only about who you point at for source.

## Attribution

* Podroid — https://github.com/ExTV/Podroid (GPLv2): QEMU build recipe, launcher,
  guest kernel configuration, initramfs design.
* QEMU — https://www.qemu.org (GPLv2): the emulator itself and TCG.
* Alpine Linux — https://alpinelinux.org: the guest distribution.
* Termux — https://termux.dev: the terminal-view/terminal-emulator sources
  Podroid vendors; this repo does not ship them (the Flutter UI renders its own
  output), but the guest-side pattern of a virtio-console agent and the
  `nativeLibraryDir` exec workaround both trace back to that community.
