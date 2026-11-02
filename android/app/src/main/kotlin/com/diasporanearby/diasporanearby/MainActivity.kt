package com.diasporanearby.diasporanearby

import android.content.Intent
import android.os.Bundle
import com.ryanheise.audioservice.AudioServiceFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceFragmentActivity() {
    companion object {
        private const val SHARE_INTENT_CHANNEL = "com.diasporanearby/share_intent"
    }

    private var latestSharedText: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        captureSharedText(intent)
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        captureSharedText(intent)
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            SHARE_INTENT_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "consumeSharedText" -> {
                    val text = latestSharedText
                    latestSharedText = null
                    result.success(text)
                }
                "getSharedText" -> {
                    result.success(latestSharedText)
                }
                "clearSharedText" -> {
                    latestSharedText = null
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        setIntent(intent)
        captureSharedText(intent)
        super.onNewIntent(intent)
    }

    private fun captureSharedText(intent: Intent?) {
        if (intent == null) return
        val action = intent.action
        if (action != Intent.ACTION_SEND && action != Intent.ACTION_SEND_MULTIPLE) {
            return
        }

        val extraText = intent.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString()?.trim()
            ?: intent.getStringExtra(Intent.EXTRA_TEXT)?.trim()
        val extraSubject = intent.getCharSequenceExtra(Intent.EXTRA_SUBJECT)?.toString()?.trim()
            ?: intent.getStringExtra(Intent.EXTRA_SUBJECT)?.trim()
        val extraTitle = intent.getCharSequenceExtra(Intent.EXTRA_TITLE)?.toString()?.trim()
            ?: intent.getStringExtra(Intent.EXTRA_TITLE)?.trim()

        var clipText: String? = null
        val clipData = intent.clipData
        if (clipData != null) {
            val parts = mutableListOf<String>()
            for (i in 0 until clipData.itemCount) {
                val item = clipData.getItemAt(i)
                val t = item?.text?.toString()?.trim()
                if (!t.isNullOrEmpty()) {
                    parts.add(t)
                }
            }
            if (parts.isNotEmpty()) {
                clipText = parts.joinToString("\n")
            }
        }

        val primaryText = when {
            !extraText.isNullOrEmpty() -> extraText
            !clipText.isNullOrEmpty() -> clipText
            else -> null
        }

        val headerText = when {
            !extraSubject.isNullOrEmpty() -> extraSubject
            !extraTitle.isNullOrEmpty() -> extraTitle
            else -> null
        }

        latestSharedText = when {
            !primaryText.isNullOrEmpty() && !headerText.isNullOrEmpty() -> {
                if (primaryText.contains(headerText, ignoreCase = true)) {
                    primaryText
                } else {
                    "$headerText\n$primaryText"
                }
            }
            !primaryText.isNullOrEmpty() -> primaryText
            !headerText.isNullOrEmpty() -> headerText
            else -> null
        }
    }
}
