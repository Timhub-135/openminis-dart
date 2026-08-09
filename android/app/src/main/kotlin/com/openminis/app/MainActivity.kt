package com.openminis.app

import android.content.Intent
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "openminis/share"
    }

    private var pendingShare: JSONObject? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "consumeShare" -> {
                    result.success(pendingShare?.toString())
                    pendingShare = null
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        pendingShare = parseShare(intent)
        // The Flutter side can re-check via consumeShare; nothing to push here.
    }

    override fun onStart() {
        super.onStart()
        // Capture a share intent (singleTop relaunch keeps the same activity).
        pendingShare = parseShare(intent)
    }

    private fun parseShare(intent: Intent?): JSONObject? {
        if (intent == null) return null
        if (intent.action != Intent.ACTION_SEND && intent.action != Intent.ACTION_SEND_MULTIPLE) {
            return null
        }
        val obj = JSONObject()
        val text = intent.getStringExtra(Intent.EXTRA_TEXT)
        val subject = intent.getStringExtra(Intent.EXTRA_SUBJECT)
        if (text != null) obj.put("sharedText", text)
        if (subject != null) obj.put("sharedSubject", subject)

        val uris = mutableListOf<String>()
        val clipdata = intent.clipData
        if (clipdata != null) {
            for (i in 0 until clipdata.itemCount) {
                val uri: Uri? = clipdata.getItemAt(i).uri
                if (uri != null) uris.add(uri.toString())
            }
        } else {
            intent.data?.let { uris.add(it.toString()) }
        }
        if (uris.isNotEmpty) obj.put("sharedUris", JSONArray(uris))
        return obj
    }
}
