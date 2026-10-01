package com.openminis.app

import android.content.Context
import android.content.res.AssetManager
import android.util.Log
import java.io.File
import java.io.FileOutputStream

/**
 * Unpacks the R2 VM payload (kernel + initramfs + Alpine squashfs + QEMU data
 * files) out of the APK's `assets/vm/` into `<filesDir>/vm` on first launch.
 *
 * Why the app must do this rather than the Dart sandbox: 200 MB of asset bytes
 * should not be copied through the Flutter/Dart heap, and Dart cannot open APK
 * assets at all. Doing it here also means the payload is unpacked before the
 * first `linux_sh` call, so the sandbox's `start()` usually finds it ready.
 *
 * Idempotent: a `.payload` file records the versionCode that wrote the payload,
 * so an app update (new kernel/squashfs) re-extracts while normal launches are
 * a single `stat`.
 */
object VmAssetInstaller {
    private const val TAG = "VmAssetInstaller"
    private const val ASSET_ROOT = "vm"

    /** Directories under [ASSET_ROOT] copied recursively. */
    private val DIRS = listOf("qemu/keymaps")

    /** Individual files under [ASSET_ROOT]. */
    private val FILES = listOf(
        "vmlinuz-virt",
        "initrd.img",
        "alpine-minis.squashfs",
        "qemu/efi-virtio.rom",
    )

    @Volatile
    private var started = false

    /** Kick off extraction (or the version check) on a background thread. */
    @Synchronized
    fun ensureInstalled(context: Context) {
        if (started) return
        started = true
        Thread({ install(context.applicationContext) }, "vm-assets").apply {
            isDaemon = true
            start()
        }
    }

    /** Blocking; safe to call from a worker. */
    fun install(context: Context) {
        val vmDir = File(context.filesDir, ASSET_ROOT)
        val marker = File(vmDir, ".payload")
        val wanted = context.packageManager
            .getPackageInfo(context.packageName, 0).longVersionCode.toString()

        if (marker.exists() && marker.readText().trim() == wanted && required(vmDir)) {
            // Touch the ready flag the Dart sandbox waits for.
            File(vmDir, ".ready").writeText(wanted)
            return
        }

        try {
            vmDir.mkdirs()
            val am: AssetManager = context.assets
            for (name in FILES) {
                copyAsset(am, "$ASSET_ROOT/$name", File(vmDir, name))
            }
            for (dir in DIRS) {
                copyAssetDir(am, "$ASSET_ROOT/$dir", File(vmDir, dir))
            }
            // The Dart side keys off this file: payload present and complete.
            marker.writeText(wanted)
            File(vmDir, ".ready").writeText(wanted)
            Log.i(TAG, "VM payload unpacked into ${vmDir.absolutePath}")
        } catch (t: Throwable) {
            // Leave the marker untouched so the next launch retries; the Dart
            // sandbox fails with a message naming the missing files.
            Log.e(TAG, "VM payload extraction failed", t)
        }
    }

    private fun required(vmDir: File): Boolean =
        FILES.all { File(vmDir, it).let { f -> f.isFile && f.length() > 0 } }

    private fun copyAsset(am: AssetManager, assetPath: String, dest: File) {
        dest.parentFile?.mkdirs()
        // Rewrite when the size differs (an APK update with a new kernel).
        val assetSize = am.open(assetPath, AssetManager.ACCESS_STREAMING).use { it.available().toLong() }
        if (dest.isFile && dest.length() == assetSize && assetSize > 0) return
        am.open(assetPath, AssetManager.ACCESS_STREAMING).use { input ->
            FileOutputStream(dest).use { output ->
                input.copyTo(output, DEFAULT_BUFFER_SIZE * 16)
                output.fd.sync()
            }
        }
        if (dest.length() != assetSize && assetSize > 0) {
            Log.w(TAG, "size mismatch for $assetPath: ${dest.length()} != $assetSize")
        }
    }

    private fun copyAssetDir(am: AssetManager, assetPath: String, dest: File) {
        val children = am.list(assetPath) ?: return
        if (children.isEmpty()) {
            copyAsset(am, assetPath, dest)
            return
        }
        dest.mkdirs()
        for (child in children) {
            copyAssetDir(am, "$assetPath/$child", File(dest, child))
        }
    }
}
