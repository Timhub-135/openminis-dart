# Android backend R2 — a QEMU VM instead of Termux/PRoot

This document describes the Android sandbox that replaced the Termux bridge:
a real Alpine Linux virtual machine, shipped inside the APK, booted with QEMU
(TCG) and driven over the guest's own virtio-console.

For the survey of the alternatives that led here (and why the others were
rejected) see `docs/android-sandbox-options.md`.

---

## 1. Why this backend exists

The previous Android path borrowed **Termux** (via the `RUN_COMMAND` broadcast)
or, before that, **PRoot**. Both depend on things a device may not grant:

| Blocker | What it breaks |
|---|---|
| `execve()` on files in `/data/data/<pkg>` is denied for apps with `targetSdk ≥ 29` (W^X, SELinux `untrusted_app` → `app_data_file:execute_no_trans`) | Any bundled shell, PRoot, or Linux userland living in the app's data dir |
| `ptrace` disabled by some ROMs/kernels | PRoot entirely (it is a ptrace-based syscall rewriter) |
| No unprivileged user namespaces (`unshare` → `EPERM`/`EINVAL`) | `bwrap`, `lxroot`, `rootlesskit`, container-style sandboxes |
| Termux not installable (no Play/F-Droid, managed device, non-Android OS) | The Termux bridge |
| 16 KB page devices | Native binaries not linked with `-Wl,-z,max-page-size=16384` |

R2 requires **none** of them:

* QEMU and its launcher are shipped as APK **native libraries** → extracted at
  install time into the native library dir, the one place Android still lets an
  app `exec()` from.
* The guest has its **own kernel**, so host `ptrace`, namespace and W^X policy
  are irrelevant to everything running inside it.
* No root, no Termux, no PRoot, no `/dev/kvm` (TCG is pure software emulation).

---

## 2. Architecture

```
                       Android app process
  ┌──────────────────────────────────────────────────────────────────────┐
  │ Flutter UI                                                           │
  │   └── AppState ── SandboxFactory.create(hostMinisDir: filesDir)      │
  │                     └── AndroidQemuSandbox            (dart_lib)     │
  │                           ├─ VmAssetInstaller  ◀── Kotlin, first run │
  │                           │     unpacks assets/vm → filesDir/vm      │
  │                           ├─ Process.start(nativeLibraryDir/…)       │
  │                           │     libpodroid-launcher.so               │
  │                           │       └─ exec libqemu-system-aarch64.so │
  │                           └─ Unix socket ── console.sock ──┐         │
  └────────────────────────────────────────────────────────────┼─────────┘
                                                               │
                                            MINIS_* line protocol
                                                               │
  ┌────────────────────────────────────────────────────────────▼─────────┐
  │ QEMU (TCG, aarch64)                                                  │
  │   vda: storage.img (sparse ext4)   vdb: alpine-minis.squashfs (ro)   │
  │   initramfs: overlay(storage.img → /) + switch_root                  │
  │   NIC: slirp (10.0.2.15/24)        9p: /mnt/minis ⇄ filesDir/vm/share│
  ├──────────────────────────────────────────────────────────────────────┤
  │ Alpine guest                                                         │
  │   /sbin/init (busybox) ── /etc/minis-rc (mounts, 9p, network)        │
  │                        └─ hvc0: /usr/local/bin/minis-agent           │
  │                                  reads MINIS_EXEC … runs `sh`        │
  └──────────────────────────────────────────────────────────────────────┘
```

### Why the payload is split this way

* **Executables** (QEMU, launcher, libslirp) → `jniLibs/arm64-v8a/`, extracted by
  the installer into the native library dir. This is the W^X workaround, and it
  is also why `useLegacyPackaging = true` is set in `android/app/build.gradle.kts`.
* **Read-only data** (kernel, initramfs, squashfs, QEMU ROM/keymaps) → APK
  `assets/vm/`, unpacked once into `filesDir/vm` by `VmAssetInstaller`.
* **Writable state** → `filesDir/vm/storage.img`, a sparse ext4 image the guest
  mounts as its overlay upper. `apk add`, `pip install`, cloned repos, files the
  agent writes: all of it survives restarts (until the app is uninstalled).

---

## 3. Layout on device

```
/data/user/0/com.openminis.app/files/vm/
  vmlinuz-virt              guest kernel              (APK asset,  ~20 MB)
  initrd.img                initramfs (overlay+switch_root) (APK asset, ~41 MB)
  alpine-minis.squashfs     read-only Alpine root     (APK asset,  ~46 MB)
  qemu/efi-virtio.rom       QEMU data files (-L)      (APK asset)
  qemu/keymaps/…            keyboard maps             (APK asset)
  storage.img               writable ext4, sparse     (created by the sandbox)
  share/                    virtio-9p ⇄ guest /mnt/minis
  run/console.sock          host ⇄ guest agent
  run/serial.sock           kernel/init console (debug)
  run/qmp.sock              QEMU monitor (clean shutdown)
  .payload / .ready         install markers written by VmAssetInstaller
```

`VmPaths` in `dart_lib/lib/src/sandbox/qemu_vm.dart` owns this contract.

---

## 4. Console protocol (`minis-agent`)

One frame per line; payloads are base64 in ≤1024-char chunks, because a Linux
tty in canonical mode caps a line at `MAX_CANON` (4096 bytes) and QEMU's
virtio-console is a tty.

```
guest → host   MINIS_READY 1
host  → guest  MINIS_PING              guest → host  MINIS_PONG

host  → guest  MINIS_EXEC <id> <chunk>    start a command, first chunk
host  → guest  MINIS_DATA <chunk>         more chunks
host  → guest  MINIS_RUN                  decode + execute
guest → host   MINIS_START <id>
               MINIS_OUT <id> <chunk>     repeated
               MINIS_END <id> <exitcode>
guest → host   MINIS_ERR <id> <reason>
```

* Commands are serialised host-side (`VmConsoleClient` chains them) and matched
  by id, so an echoed byte can never be mistaken for a result.
* Output is capped at 8 MiB per command, then truncated with a marker.
* `exec(..., timeout:)` wraps the command in `timeout -k 5 Ns` **inside the
  guest**, and the host additionally arms a frame-timeout guard so a wedged
  guest cannot hang a tool call forever.
* File IO: paths under `/mnt/minis/**` are read/written directly on the host
  side of the 9p share (no console traffic); everything else goes through the
  agent as base64.

The guest side lives in `android/vm/guest/` and is syntax-checked by the Dart
test suite:

```
android/vm/guest/usr/local/bin/minis-agent    the endpoint above
android/vm/guest/etc/minis-rc                 sysinit (mounts, 9p, network)
android/vm/guest/etc/inittab                  busybox init: no login, no getty
android/vm/guest/etc/fstab
```

---

## 5. Lifecycle

| Action | Behaviour |
|---|---|
| `start()` | Wait for the payload marker → ensure `storage.img` → **attach** to a live console if one answers (survives Flutter hot restarts) → otherwise launch QEMU and wait for `MINIS_READY` |
| first boot | The initramfs `e2fsck`/`mkfs.ext4`s the all-zero `storage.img`; boot takes ~10–30 s under TCG |
| later boots | Overlay stack mounts straight away; ~6–15 s |
| `stop()` | QMP `quit` (clean ext4 shutdown) with SIGKILL fallback, then socket cleanup |
| app exit | `libpodroid-launcher.so` sets `PR_SET_PDEATHSIG(SIGKILL)`, so the VM dies with the app instead of lingering as an orphan |

Tunables live in `VmConfig` (`ramMb`, `cpus`, `storageMb`, `hostFwd`,
`shareEnabled`, `extraQemuArgs`, `kernelCmdlineExtra`) and are passed through
`SandboxFactory.create(vmConfig: …)`.

---

## 6. Building

```sh
# 1. kernel / initramfs / QEMU / launcher  (from the upstream Podroid release)
./tools/fetch-podroid-artifacts.sh

# 2. our own Alpine rootfs with minis-agent baked in
#    (needs an aarch64 Linux host with apk-tools + squashfs-tools)
./tools/build-vm-rootfs.sh

# 3. the app
flutter pub get
flutter build apk --debug      # or --release
```

Verification that matters:

* `dart test` in `dart_lib/` — the protocol, argv contract, sparse image, file
  IO and the guest scripts are covered by unit tests (no device needed).
* After installing, `linux_sh('cat /etc/minis-vm-release; uname -a')` should
  answer from the guest. `AndroidQemuSandbox.status()` returns the same as a
  diagnostic summary.
* The APK must contain `lib/arm64-v8a/libqemu-system-aarch64.so` **uncompressed
  and extracted** (`unzip -l` shows it, and `run-as` can exec it).

---

## 7. Limitations / not done yet

* **Speed.** TCG is software emulation: expect ~1/5–1/20 native, fine for the
  agent's shells/builds, poor for heavy compiles or ML.
* **APK size.** ~145 MB of payload on top of the Flutter engine. `arm64-v8a`
  only; nothing else is supported.
* **No foreground service yet.** The VM lives as long as the app process. A
  service + `START_STICKY` would keep it alive across app switches.
* **`run()` is not truly streaming** — it yields the whole output once, matching
  the previous Termux implementation. The protocol has per-chunk frames, so a
  streaming version is a small change to `VmConsoleClient`.
* **AVF/pKVM fast path** is not implemented: on devices that expose the Android
  Virtualization Framework with non-protected VMs, `AvfEngine`-style hardware
  virtualisation would remove the TCG penalty (it needs two `adb pm grant`s and
  is not universally available — hence QEMU stays the default).
* **GUI apps** (X11/Wayland) are not wired; the guest has no display server.
* **Port forwarding** is limited to the `hostFwd` rules given at launch; adding
  rules at runtime needs a QMP client (`netdev_add`/`hostfwd_add`).
* **`/sdcard` sharing** is not wired to the 9p share yet (Android scoped
  storage makes it a permission question, not a protocol one).
* **Sandbox concurrency**: one VM, one console → commands are serialised by
  design. Parallel tool calls queue.

---

## 8. Provenance and licensing

See `NOTICE-vm-payload.md`. Short version: QEMU and the guest kernel are GPLv2
(from upstream Podroid's build), `libslirp` is BSD-3-Clause, Alpine packages keep
their own licences. They are shipped as **separate executables/files invoked by
the app**, not linked into it — but the obligations (source availability,
attribution) still apply to whoever distributes the APK.
