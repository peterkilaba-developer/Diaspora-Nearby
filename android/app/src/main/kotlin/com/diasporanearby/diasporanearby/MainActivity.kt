package com.diasporanearby.diasporanearby

import android.content.Intent
import android.os.Bundle
import com.ryanheise.audioservice.AudioServiceFragmentActivity
import com.ryanheise.audioservice.AudioServicePlugin
import id.flutter.flutter_background_service.Config
import id.flutter.flutter_background_service.WatchdogReceiver
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceFragmentActivity() {
    companion object {
        private const val SHARE_INTENT_CHANNEL = "com.diasporanearby/share_intent"
    }

    private var latestSharedText: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        // Ensure legacy background location watchdog/boot alarms from older app
        // versions stay disabled on Android so a secondary background engine
        // cannot contend with the foreground UI engine.
        disableLegacyBackgroundService()

        val wasEngineRunning = FlutterEngineCache.getInstance()
            .get(AudioServicePlugin.getFlutterEngineId())
            ?.dartExecutor
            ?.isExecutingDart == true

        captureSharedText(intent)
        super.onCreate(savedInstanceState)

        // When AudioServiceFragmentActivity uses a cached FlutterEngine,
        // FlutterFragment skips Activity.configureFlutterEngine(). Always bind
        // our share-intent channel directly to the shared engine here.
        val sharedEngine = AudioServicePlugin.getFlutterEngine(this)
        registerShareIntentChannel(sharedEngine)

        // If the cached engine was already executing Dart (warm Activity
        // recreation), initialRoute is ignored by Flutter. Forward incoming
        // ACTION_VIEW deep links explicitly to GoRouter.
        if (wasEngineRunning && intent?.action == Intent.ACTION_VIEW) {
            val dataString = intent?.dataString
            if (!dataString.isNullOrEmpty()) {
                sharedEngine.navigationChannel.pushRouteInformation(dataString)
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        captureSharedText(intent)
        super.configureFlutterEngine(flutterEngine)
        registerShareIntentChannel(flutterEngine)
    }

    private fun registerShareIntentChannel(flutterEngine: FlutterEngine) {
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

    private fun disableLegacyBackgroundService() {
        try {
            val config = Config(applicationContext)
            if (config.isAutoStartOnBoot || !config.isManuallyStopped) {
                config.isAutoStartOnBoot = false
                config.isManuallyStopped = true
            }
            WatchdogReceiver.remove(applicationContext)
        } catch (_: Throwable) {
            // Best effort — never block Activity startup
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
