package com.clipboardsync.clipboard_sync

import android.animation.Animator
import android.animation.AnimatorListenerAdapter
import android.app.Service
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.graphics.PixelFormat
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.view.animation.DecelerateInterpolator
import android.widget.LinearLayout
import android.widget.TextView
import android.graphics.drawable.GradientDrawable

/**
 * 复制后弹出的小型同步按钮
 *
 * 动画：从屏幕右侧滑入 + 放大 + 淡入（250ms，Decelerate）
 * 点击：读剪贴板 → 成功则同步 + ✓，失败则自动打开 Ccv 兜底
 * 超时：3 秒无操作自动消失
 */
class SyncButtonService : Service() {

    companion object {
        const val TAG = "CcvSyncBtn"
        const val EXTRA_AUTO_SYNC = "auto_sync_on_resume"

        fun show(context: Context) {
            context.startService(Intent(context, SyncButtonService::class.java).apply { action = "show" })
        }
    }

    private var wm: WindowManager? = null
    private var view: View? = null
    private var label: TextView? = null
    private val handler = Handler(Looper.getMainLooper())
    private var dismissRunnable: Runnable? = null
    private var showing = false

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        wm = getSystemService(WINDOW_SERVICE) as WindowManager
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == "show" && !showing) show()
        return START_NOT_STICKY
    }

    // ═══════════════════════════════════════════
    // 显示按钮
    // ═══════════════════════════════════════════

    private fun show() {
        showing = true
        val dp = resources.displayMetrics.density
        val size = (56 * dp).toInt()

        // ── 容器 ──
        val container = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            layoutParams = LinearLayout.LayoutParams(size, size)
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(0xFF1565C0.toInt())
                setStroke((2.5f * dp).toInt(), 0xAAFFFFFF.toInt())
            }
            elevation = 12f * dp
            alpha = 0f
            scaleX = 0.8f
            scaleY = 0.8f
            translationX = 80f * dp
        }

        // 同步图标
        val icon = TextView(this).apply {
            text = "⇄"
            textSize = 18f
            setTextColor(0xFFFFFFFF.toInt())
            gravity = Gravity.CENTER
        }
        container.addView(icon)

        // 状态标签
        label = TextView(this).apply {
            text = ""
            textSize = 10f
            setTextColor(0xFFFFFFFF.toInt())
            gravity = Gravity.CENTER
            visibility = View.GONE
        }
        container.addView(label)

        // 点击
        container.setOnClickListener { onClick() }

        view = container

        // ── Window 参数 ──
        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION") WindowManager.LayoutParams.TYPE_PHONE
        }

        val params = WindowManager.LayoutParams(size, size, type,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                    WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.CENTER_VERTICAL or Gravity.RIGHT
            x = (8 * dp).toInt()
            y = 0
        }

        wm?.addView(container, params)

        // ── 入场动画：滑入 + 放大 + 淡入 ──
        container.animate()
            .translationX(0f)
            .scaleX(1f).scaleY(1f)
            .alpha(1f)
            .setDuration(250)
            .setInterpolator(DecelerateInterpolator())
            .start()

        // ── 3 秒自动消失 ──
        dismissRunnable = Runnable { dismiss() }
        handler.postDelayed(dismissRunnable!!, 3000)
    }

    // ═══════════════════════════════════════════
    // 点击处理
    // ═══════════════════════════════════════════

    private fun onClick() {
        handler.removeCallbacks(dismissRunnable!!)
        MainActivity.logToFile("SYNC_BTN", "clicked")

        // 读剪贴板
        val cm = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        val text = try {
            if (cm.hasPrimaryClip() && (cm.primaryClip?.itemCount ?: 0) > 0) {
                cm.primaryClip!!.getItemAt(0).coerceToText(this).toString()
            } else ""
        } catch (e: Exception) {
            MainActivity.logToFile("CLIPBOARD", "read failed reason=${e.message}")
            ""
        }

        if (text.isNotBlank()) {
            // 情况 A：读取成功 → 同步
            MainActivity.logToFile("CLIPBOARD", "read success text=\"${text.take(60)}\"")

            val sink = MainActivity.a11yEventSink
            if (sink != null) {
                sink.success(mapOf(
                    "time" to java.text.SimpleDateFormat("HH:mm:ss.SSS", java.util.Locale.getDefault()).format(java.util.Date()),
                    "eventType" to "SYNC_BTN",
                    "packageName" to "SyncButton",
                    "className" to "SyncButtonService",
                    "eventText" to "同步按钮发送",
                    "sourceText" to text
                ))
                MainActivity.logToFile("UPLOAD", "success")
            }

            showResult(true)
        } else {
            // 情况 B：读取失败 → 自动打开 Ccv
            MainActivity.logToFile("CLIPBOARD", "read failed → auto launch")
            MainActivity.logToFile("AUTO_RECOVERY", "launch CCV")

            val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
            if (launchIntent != null) {
                launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
                launchIntent.putExtra(EXTRA_AUTO_SYNC, true)
                startActivity(launchIntent)
            }
            handler.postDelayed({ dismiss() }, 400)
        }
    }

    // ═══════════════════════════════════════════
    // 结果反馈
    // ═══════════════════════════════════════════

    private fun showResult(success: Boolean) {
        val container = view ?: return

        // 变绿色
        if (success) {
            (container.background as? GradientDrawable)?.setColor(0xFF2E7D32.toInt())
            label?.apply { text = "✓ 已同步"; visibility = View.VISIBLE }
        } else {
            label?.apply { text = "重试"; visibility = View.VISIBLE }
        }

        // 轻微震动
        try {
            val vibrator = getSystemService(VIBRATOR_SERVICE) as? Vibrator
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                vibrator?.vibrate(VibrationEffect.createOneShot(30, VibrationEffect.DEFAULT_AMPLITUDE))
            } else {
                @Suppress("DEPRECATION") vibrator?.vibrate(30)
            }
        } catch (_: Exception) {}

        handler.postDelayed({ dismiss() }, 800)
    }

    // ═══════════════════════════════════════════
    // 消失
    // ═══════════════════════════════════════════

    private fun dismiss() {
        showing = false
        handler.removeCallbacks(dismissRunnable!!)

        val v = view
        if (v != null && wm != null) {
            v.animate()
                .translationX(80f * resources.displayMetrics.density)
                .scaleX(0.8f).scaleY(0.8f)
                .alpha(0f)
                .setDuration(150)
                .setInterpolator(DecelerateInterpolator())
                .setListener(object : AnimatorListenerAdapter() {
                    override fun onAnimationEnd(animation: Animator) {
                        try { wm?.removeView(v) } catch (_: Exception) {}
                        view = null
                        stopSelf()
                    }
                })
                .start()
        } else {
            stopSelf()
        }
    }

    override fun onDestroy() {
        dismiss()
        super.onDestroy()
    }
}
