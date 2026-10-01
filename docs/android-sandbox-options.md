# Android sandbox options — why R2 (QEMU VM) and not the alternatives

Survey done while replacing the Android backend. Everything below is stated with
its preconditions; "cost" is engineering + runtime cost, not a preference.

| Layer of blockage | Symptom | Consequence |
|---|---|---|
| **A.** `execve()` on app data denied (`targetSdk ≥ 29`, SELinux `untrusted_app` → `app_data_file:execute_no_trans`) | `error=13 Permission denied` when spawning a bundled binary | No PRoot/Termux-style bootstrap in `/data/data/<pkg>` |
| **B.** `ptrace` restricted by ROM/kernel | `PTRACE_TRACEME: Operation not permitted` | PRoot cannot start at all |
| **C.** No unprivileged user namespaces | `unshare(CLONE_NEWUSER) = EINVAL`, `unshare(CLONE_NEWNS) = EPERM` | `bwrap`, `lxroot`, `rootlesskit` all fail on stock kernels |
| **D.** Termux not installable / not permitted | install rejected, or the broadcast never arrives | The Termux bridge is dead |
| **E.** 16 KB page devices, or armeabi-v7a-only hardware | `ELF … alignment`, install-time validation | Native payload must be built/aligned correctly |

## Options considered

**R1 — jniLibs workaround, keep PRoot.** Ship every executable as
`lib<name>.so` in `jniLibs/arm64-v8a/`; Android extracts them to
`/data/app/…/lib/arm64/` (mode `rwxr-xr-x`, SELinux `apk_data_file`), which *is*
executable from an app. Symlink them into the rootfs built in `filesDir`.
*Works when A is the only blocker.* Costs: executables are read-only, so
anything the agent compiles or `apk add`s afterwards still cannot be executed;
`-f`/`conffiles` checks misbehave on symlinks; needs a Termux-style bootstrap
build. Rejected as the primary backend for those limits — not for feasibility.

**R2 — QEMU system mode (TCG) in-app. CHOSEN.** The APK carries QEMU, a kernel,
an initramfs and an Alpine squashfs; the guest gets a writable ext4 overlay for
persistence. Needs none of A–C. Costs: ~145 MB of payload, arm64 only, boot of a
few seconds, TCG speed.

**R3 — AVF/pKVM.** Android's Virtualization Framework runs the guest on real
cores (near-native). Third-party apps must link stubs `compileOnly` and have the
user run `pm grant … MANAGE_VIRTUAL_MACHINE` / `USE_CUSTOM_VIRTUAL_MACHINE`
(adb or Shizuku). Availability is OEM-dependent: reports put non-protected VMs
out of reach on Snapdragon stock firmware, while Android 15+ mandates *some* AVF.
*Kept as a future fast path*, not the default — it cannot be assumed.

**R4 — root: chroot + namespaces.** Fastest and simplest when root exists. Out of
scope: the target device has no root.

**R5 — qemu-user / DBI (QBDI) as a PRoot substitute.** Path translation without
ptrace. Inside this sandbox `qemu-aarch64 -L <prefix>` did prefix the *main*
process's absolute paths but forked children lost it — and the sandbox itself
runs under PRoot, so the experiment cannot be extrapolated to a device. Not
pursued; R2 sidesteps the question.

**R6 — not Android.** If the target were HarmonyOS NEXT / a car head unit / RTOS,
APKs would not apply at all; that would need its own stack.

## What R2 does *not* solve

* Speed: no hardware virtualisation → TCG.
* Size: the payload dominates the APK.
* Background lifetime: without a foreground service the VM dies with the app
  process (by design, via `PR_SET_PDEATHSIG`).
* GUI: no display server in the guest (X11 would need an in-app viewer).
