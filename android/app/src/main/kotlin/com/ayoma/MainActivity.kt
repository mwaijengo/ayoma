package com.ayoma

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var player: AyomaPlayerPlugin? = null

    /** Screenshots and screen recording are blocked unless Dart allows them (Settings). */
    override fun onCreate(savedInstanceState: Bundle?) {
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "ayoma/screen")
            .setMethodCallHandler { call, result ->
                if (call.method == "setSecure") {
                    if (call.argument<Boolean>("secure") != false) {
                        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    } else {
                        window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    }
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }
        player = AyomaPlayerPlugin(
            applicationContext,
            flutterEngine.dartExecutor.binaryMessenger,
            flutterEngine.renderer,
        ) { on ->
            if (on) {
                window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            } else {
                window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            }
        }
        createAlertsChannel()
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        player?.dispose()
        player = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    /** Matches the channel ID the server sends with admin notifications. */
    private fun createAlertsChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            "uhurumax_alerts",
            "Taarifa za AyomaMax",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply { description = "Vifurushi, mechi na taarifa muhimu" }
        getSystemService(NotificationManager::class.java)?.createNotificationChannel(channel)
    }
}
