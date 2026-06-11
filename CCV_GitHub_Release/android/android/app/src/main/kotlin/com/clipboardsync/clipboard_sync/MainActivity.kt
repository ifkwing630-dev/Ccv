package com.clipboardsync.clipboard_sync

import android.content.ClipboardManager
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.os.PowerManager
import android.provider.Settings
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.text.SimpleDateFormat
import java.util.*

class MainActivity : FlutterActivity() {

    companion object {
        const val SYNC_CHANNEL = "ccv/sync_service"
        const val A11Y_CHANNEL = "ccv/a11y_events"
        var a11yEventSink: EventChannel.EventSink? = null

        // 日志文件
        private var logFile: File? = null

        fun logToFile(tag: String, msg: String) {
            Log.i(tag, msg)
            try {
                if (logFile == null) {
                    val dir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
                    logFile = File(dir, "ccv_log.txt")
                }
                val ts = SimpleDateFormat("HH:mm:ss.SSS", Locale.getDefault()).format(Date())
                logFile?.appendText("$ts [$tag] $msg\n")
            } catch (_: Exception) {}
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // 每次启动清空旧日志
        try {
            val dir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
            val f = java.io.File(dir, "ccv_log.txt")
            f.writeText("")
        } catch (_: Exception) {}
        logToFile("ACTIVITY", "onCreate — log reset")
    }

    override fun onResume() {
        super.onResume()
        logToFile("ACTIVITY", "onResume")

        // 自动同步恢复：SyncButton 读剪贴板失败后打开 Ccv，自动补齐同步
        if (intent?.getBooleanExtra("auto_sync_on_resume", false) == true) {
            logToFile("AUTO_RECOVERY", "onResume with auto_sync flag")
            intent?.removeExtra("auto_sync_on_resume")

            // 延迟等 Flutter 初始化完成
            android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                val cm = getSystemService(CLIPBOARD_SERVICE) as ClipboardManager
                val text = try {
                    if (cm.hasPrimaryClip() && (cm.primaryClip?.itemCount ?: 0) > 0) {
                        cm.primaryClip!!.getItemAt(0).coerceToText(this).toString()
                    } else ""
                } catch (e: Exception) { "" }

                if (text.isNotBlank()) {
                    logToFile("AUTO_RECOVERY", "clipboard success: \"${text.take(60)}\"")
                    a11yEventSink?.success(mapOf(
                        "time" to java.text.SimpleDateFormat("HH:mm:ss.SSS", java.util.Locale.getDefault()).format(java.util.Date()),
                        "eventType" to "AUTO_SYNC",
                        "packageName" to "MainActivity",
                        "className" to "auto_sync",
                        "eventText" to "自动恢复同步",
                        "sourceText" to text
                    ))
                } else {
                    logToFile("AUTO_RECOVERY", "clipboard still empty")
                }
            }, 500)
        }
    }

    override fun onPause() {
        super.onPause()
        logToFile("ACTIVITY", "onPause")
    }

    override fun onStop() {
        super.onStop()
        logToFile("ACTIVITY", "onStop")
    }

    override fun onDestroy() {
        super.onDestroy()
        logToFile("ACTIVITY", "onDestroy")
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SYNC_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startForegroundService" -> {
                        ClipboardSyncService.start(this)
                        result.success(true)
                    }
                    "stopForegroundService" -> {
                        ClipboardSyncService.stop(this)
                        result.success(true)
                    }
                    "isIgnoringBatteryOpt" -> {
                        result.success(isBatteryOptimizationDisabled())
                    }
                    "requestBatteryOpt" -> {
                        openBatteryOptimizationSettings()
                        result.success(true)
                    }
                    "readClipboard" -> {
                        result.success(readSystemClipboard())
                    }
                    "startClipboardListener" -> {
                        ClipboardListenerService.start(this)
                        result.success(true)
                    }
                    "stopClipboardListener" -> {
                        ClipboardListenerService.stop(this)
                        result.success(true)
                    }
                    "startFloatingBall" -> {
                        FloatingBallService.start(this)
                        result.success(true)
                    }
                    "stopFloatingBall" -> {
                        FloatingBallService.stop(this)
                        result.success(true)
                    }
                    "checkAccessibility" -> {
                        result.success(isAccessibilityEnabled())
                    }
                    "openAccessibilitySettings" -> {
                        startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
                        result.success(true)
                    }
                    "checkOverlay" -> {
                        result.success(Settings.canDrawOverlays(this))
                    }
                    "openOverlaySettings" -> {
                        startActivity(Intent(
                            Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                            Uri.parse("package:$packageName")
                        ))
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, A11Y_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, sink: EventChannel.EventSink) {
                    a11yEventSink = sink
                    logToFile("EVENT_CHANNEL", "Flutter subscribed (onListen)")
                }
                override fun onCancel(args: Any?) {
                    a11yEventSink = null
                    logToFile("EVENT_CHANNEL", "Flutter unsubscribed (onCancel)")
                }
            })
    }

    // ── 无障碍检测 ──
    private fun isAccessibilityEnabled(): Boolean {
        val enabled = Settings.Secure.getString(contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES) ?: return false
        return enabled.contains("CcvAccessibilityService")
    }

    // ── 系统剪贴板直接读取 ──
    private fun readSystemClipboard(): String {
        val cm = getSystemService(CLIPBOARD_SERVICE) as ClipboardManager
        val clip = cm.primaryClip
        val text = if (clip != null && clip.itemCount > 0) {
            clip.getItemAt(0).text?.toString() ?: ""
        } else ""
        return "$text|${System.currentTimeMillis()}"
    }

    // ── 电池优化 ──
    private fun isBatteryOptimizationDisabled(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true
        val pm = getSystemService(POWER_SERVICE) as PowerManager
        return pm.isIgnoringBatteryOptimizations(packageName)
    }

    private fun openBatteryOptimizationSettings() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            startActivity(Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                data = Uri.parse("package:$packageName")
            })
        }
    }
}
