package com.clipboardsync.clipboard_sync

import android.accessibilityservice.AccessibilityService
import android.util.Log
import android.view.accessibility.AccessibilityEvent

class CcvAccessibilityService : AccessibilityService() {

    companion object {
        const val TAG = "CcvA11y"
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        Log.i(TAG, "═══ 无障碍服务已连接 ═══")

        // 推送一条启动事件，验证 Dart ↔ Kotlin 通道
        val sink = MainActivity.a11yEventSink
        if (sink != null) {
            sink.success(mapOf(
                "time" to java.text.SimpleDateFormat("HH:mm:ss", java.util.Locale.getDefault()).format(java.util.Date()),
                "eventType" to "SERVICE_START",
                "packageName" to "com.clipboardsync.clipboard_sync",
                "className" to "CcvAccessibilityService",
                "eventText" to "无障碍服务已连接 ✅",
                "sourceText" to "通道正常"
            ))
        }
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent) {
        val pkg = event.packageName?.toString() ?: "?"
        if (pkg == "com.clipboardsync.clipboard_sync") return

        val typeName = eventTypeToString(event.eventType)
        val cls = event.className?.toString() ?: "?"
        val timeStr = java.text.SimpleDateFormat("HH:mm:ss.SSS", java.util.Locale.getDefault())
            .format(java.util.Date())

        val eventTxt = buildString {
            for (i in 0 until event.text.size) {
                if (i > 0) append(" | ")
                append(event.text[i])
            }
        }

        Log.i(TAG, "[$typeName] pkg=$pkg | class=$cls | eventText=[$eventTxt]")
        pushToFlutter(timeStr, typeName, pkg, cls, eventTxt, "")

        // ── 关键词匹配 → 弹出同步按钮（覆盖微信等依赖 Toast 的 App）──
        val lower = eventTxt.lowercase()
        val matched = listOf(
            "已复制", "复制成功", "已拷贝", "已复制到剪贴板", "复制到剪贴板",
            "copied", "copy successful", "copied to clipboard",
            "link copied", "text copied",
            "クリップボードにコピー", "コピーしました"
        ).firstOrNull { lower.contains(it.lowercase()) }

        if (matched != null) {
            Log.i(TAG, "keyword matched: \"$matched\" → show SyncButton")
            SyncButtonService.show(this)
        }
    }

    private fun pushToFlutter(
        time: String, type: String, pkg: String, cls: String,
        eventTxt: String, srcTxt: String
    ) {
        val sink = MainActivity.a11yEventSink ?: return
        try {
            sink.success(mapOf(
                "time" to time, "eventType" to type,
                "packageName" to pkg, "className" to cls,
                "eventText" to eventTxt, "sourceText" to srcTxt
            ))
        } catch (_: Exception) {}
    }

    override fun onInterrupt() { Log.i(TAG, "服务中断") }
    override fun onDestroy() { super.onDestroy(); Log.i(TAG, "服务销毁") }

    private fun eventTypeToString(type: Int): String = when (type) {
        AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED -> "WINDOW_STATE"
        AccessibilityEvent.TYPE_VIEW_CLICKED -> "CLICKED"
        AccessibilityEvent.TYPE_VIEW_LONG_CLICKED -> "LONG_CLICKED"
        AccessibilityEvent.TYPE_VIEW_TEXT_CHANGED -> "TEXT_CHANGED"
        AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED -> "CONTENT_CHANGED"
        AccessibilityEvent.TYPE_VIEW_SCROLLED -> "SCROLLED"
        AccessibilityEvent.TYPE_VIEW_TEXT_SELECTION_CHANGED -> "TEXT_SELECTION"
        AccessibilityEvent.TYPE_ANNOUNCEMENT -> "ANNOUNCEMENT"
        AccessibilityEvent.TYPE_NOTIFICATION_STATE_CHANGED -> "NOTIFICATION"
        AccessibilityEvent.TYPE_WINDOWS_CHANGED -> "WINDOWS_CHANGED"
        AccessibilityEvent.TYPE_VIEW_CONTEXT_CLICKED -> "CONTEXT_CLICKED"
        else -> "TYPE_$type"
    }
}
