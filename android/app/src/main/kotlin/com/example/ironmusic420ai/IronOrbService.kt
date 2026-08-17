package com.example.ironmusic420ai

import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PixelFormat
import android.graphics.RadialGradient
import android.graphics.Shader
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.provider.Settings
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import java.util.Random
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.min
import kotlin.math.sin

class IronOrbService : Service() {
    companion object {
        const val ACTION_START = "com.example.ironmusic420ai.START_IRON_ORB"
        const val ACTION_STOP = "com.example.ironmusic420ai.STOP_IRON_ORB"
        const val PREFS = "iron_orb_preferences"
        const val KEY_ENABLED = "orb_enabled"

        @Volatile
        var isRunning = false
            private set

        @Volatile
        private var activeInstance: IronOrbService? = null

        fun updateVisualState(state: String) {
            activeInstance?.applyVisualState(state)
        }
    }

    private val handler = Handler(Looper.getMainLooper())
    private val random = Random()
    private lateinit var windowManager: WindowManager
    private var orbView: IronOrbView? = null
    private var layoutParams: WindowManager.LayoutParams? = null
    private var targetX = 0f
    private var targetY = 0f
    private var visualState = "idle"
    private var lastTick = 0L
    private var nextTargetAt = 0L

    private val moveRunnable = object : Runnable {
        override fun run() {
            val view = orbView ?: return
            val params = layoutParams ?: return
            val now = android.os.SystemClock.elapsedRealtime()
            val deltaSeconds = if (lastTick == 0L) 0.033f
                else ((now - lastTick).coerceIn(12L, 80L) / 1000f)
            lastTick = now

            val bounds = screenBounds()
            val maxX = (bounds.first - view.measuredWidth).coerceAtLeast(dp(1))
            val minY = dp(34)
            val maxY = (bounds.second - view.measuredHeight - dp(92)).coerceAtLeast(minY)

            if (
                now >= nextTargetAt ||
                targetX !in 0f..maxX.toFloat() ||
                targetY !in minY.toFloat()..maxY.toFloat()
            ) {
                chooseNewTarget(maxX, minY, maxY, now)
            }

            val dx = targetX - params.x
            val dy = targetY - params.y
            val distance = hypot(dx.toDouble(), dy.toDouble()).toFloat()
            if (distance < dp(10)) {
                chooseNewTarget(maxX, minY, maxY, now)
            } else {
                val speedDp = when (visualState) {
                    "listening" -> 42f
                    "thinking" -> 56f
                    "speaking" -> 34f
                    else -> 24f
                }
                val step = dpFloat(speedDp) * deltaSeconds
                params.x = (params.x + dx / distance * min(step, distance))
                    .toInt()
                    .coerceIn(0, maxX)
                params.y = (params.y + dy / distance * min(step, distance))
                    .toInt()
                    .coerceIn(minY, maxY)
                try {
                    windowManager.updateViewLayout(view, params)
                } catch (_: Exception) {
                    return
                }
            }

            view.advance(deltaSeconds, visualState, atan2(dy, dx))
            handler.postDelayed(this, 33L)
        }
    }

    override fun onCreate() {
        super.onCreate()
        activeInstance = this
        windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        if (!Settings.canDrawOverlays(this)) {
            stopSelf()
            return
        }
        attachOrb()
        isRunning = true
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                stopSelf()
                return START_NOT_STICKY
            }
            ACTION_START, null -> {
                if (!Settings.canDrawOverlays(this)) {
                    stopSelf()
                    return START_NOT_STICKY
                }
                if (orbView == null) attachOrb()
            }
        }
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        handler.removeCallbacks(moveRunnable)
        orbView?.let { view ->
            try {
                windowManager.removeView(view)
            } catch (_: Exception) {
                // The overlay may already be detached by Android.
            }
        }
        orbView = null
        layoutParams = null
        isRunning = false
        if (activeInstance === this) activeInstance = null
        super.onDestroy()
    }

    private fun attachOrb() {
        if (orbView != null) return
        val size = dp(96)
        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }
        val params = WindowManager.LayoutParams(
            size,
            size,
            type,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = dp(24)
            y = dp(180)
        }

        val view = IronOrbView(this).apply {
            contentDescription = "Живата сфера на Hey Iron"
            setOnClickListener { openConversation() }
        }
        windowManager.addView(view, params)
        orbView = view
        layoutParams = params
        lastTick = 0L
        nextTargetAt = 0L
        handler.removeCallbacks(moveRunnable)
        handler.post(moveRunnable)
    }

    private fun chooseNewTarget(
        maxX: Int,
        minY: Int,
        maxY: Int,
        now: Long,
    ) {
        targetX = if (maxX <= 0) 0f else random.nextInt(maxX + 1).toFloat()
        val verticalSpace = (maxY - minY).coerceAtLeast(1)
        targetY = (minY + random.nextInt(verticalSpace + 1)).toFloat()
        nextTargetAt = now + 3_800L + random.nextInt(4_200)
    }

    private fun applyVisualState(state: String) {
        handler.post {
            visualState = when (state.lowercase()) {
                "listening", "thinking", "speaking" -> state.lowercase()
                else -> "idle"
            }
            orbView?.setVisualState(visualState)
        }
    }

    private fun openConversation() {
        applyVisualState("listening")
        startActivity(
            Intent(this, MainActivity::class.java).apply {
                putExtra("iron_section", 0)
                putExtra("iron_orb_conversation", true)
                addFlags(
                    Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_CLEAR_TOP or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP,
                )
            },
        )
    }

    private fun screenBounds(): Pair<Int, Int> {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val bounds = windowManager.currentWindowMetrics.bounds
            bounds.width() to bounds.height()
        } else {
            @Suppress("DEPRECATION")
            resources.displayMetrics.widthPixels to resources.displayMetrics.heightPixels
        }
    }

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()
    private fun dpFloat(value: Float): Float = value * resources.displayMetrics.density
}

private class IronOrbView(context: Context) : View(context) {
    private val density = resources.displayMetrics.density
    private val shellPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val ringPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeCap = Paint.Cap.ROUND
    }
    private val leafPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.FILL
    }
    private val veinPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeCap = Paint.Cap.ROUND
    }
    private var phase = 0f
    private var direction = 0f
    private var state = "idle"
    private var downX = 0f
    private var downY = 0f

    fun setVisualState(value: String) {
        state = value
        invalidate()
    }

    fun advance(deltaSeconds: Float, value: String, travelDirection: Float) {
        state = value
        direction = travelDirection
        val pace = when (state) {
            "listening" -> 2.5f
            "thinking" -> 3.5f
            "speaking" -> 4.2f
            else -> 1.5f
        }
        phase = (phase + deltaSeconds * pace) % 6.2831855f
        invalidate()
    }

    override fun onTouchEvent(event: MotionEvent): Boolean {
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                downX = event.rawX
                downY = event.rawY
                animate().scaleX(0.92f).scaleY(0.92f).setDuration(90L).start()
                return true
            }
            MotionEvent.ACTION_UP -> {
                animate().scaleX(1f).scaleY(1f).setDuration(130L).start()
                val moved = hypot(
                    (event.rawX - downX).toDouble(),
                    (event.rawY - downY).toDouble(),
                )
                if (moved < 18f * density) performClick()
                return true
            }
            MotionEvent.ACTION_CANCEL -> {
                animate().scaleX(1f).scaleY(1f).setDuration(130L).start()
                return true
            }
        }
        return super.onTouchEvent(event)
    }

    override fun performClick(): Boolean {
        super.performClick()
        return true
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val cx = width / 2f
        val cy = height / 2f
        val radius = min(width, height) * 0.43f
        val pulse = 0.5f + 0.5f * sin(phase)
        val primary = when (state) {
            "listening" -> Color.rgb(65, 235, 255)
            "thinking" -> Color.rgb(255, 196, 48)
            "speaking" -> Color.rgb(96, 255, 142)
            else -> Color.rgb(0, 255, 112)
        }

        shellPaint.shader = RadialGradient(
            cx - cos(direction) * radius * 0.18f,
            cy - sin(direction) * radius * 0.18f,
            radius * 1.28f,
            intArrayOf(
                Color.argb(235, 5, 30, 16),
                Color.argb(220, Color.red(primary) / 5, Color.green(primary) / 3, Color.blue(primary) / 5),
                Color.argb(25, Color.red(primary), Color.green(primary), Color.blue(primary)),
                Color.TRANSPARENT,
            ),
            floatArrayOf(0f, 0.48f, 0.78f, 1f),
            Shader.TileMode.CLAMP,
        )
        canvas.drawCircle(cx, cy, radius * (1f + pulse * 0.035f), shellPaint)
        shellPaint.shader = null

        ringPaint.color = Color.argb((120 + pulse * 90).toInt(), Color.red(primary), Color.green(primary), Color.blue(primary))
        ringPaint.strokeWidth = 1.5f * density
        canvas.drawCircle(cx, cy, radius * 0.88f, ringPaint)
        ringPaint.strokeWidth = 2.4f * density
        val sweep = when (state) {
            "thinking" -> 210f
            "speaking" -> 150f + pulse * 80f
            else -> 115f
        }
        canvas.drawArc(
            cx - radius,
            cy - radius,
            cx + radius,
            cy + radius,
            phase * 57.2958f,
            sweep,
            false,
            ringPaint,
        )

        val leafScale = radius * (0.53f + pulse * 0.025f)
        leafPaint.color = Color.argb(235, 33, 255, 117)
        veinPaint.color = Color.argb(190, 190, 255, 214)
        veinPaint.strokeWidth = 0.75f * density
        val angles = floatArrayOf(-58f, -38f, -19f, 0f, 19f, 38f, 58f)
        val lengths = floatArrayOf(0.58f, 0.78f, 0.92f, 1.08f, 0.92f, 0.78f, 0.58f)
        for (index in angles.indices) {
            canvas.save()
            canvas.rotate(angles[index], cx, cy + leafScale * 0.34f)
            val length = leafScale * lengths[index]
            val halfWidth = leafScale * if (index == 3) 0.17f else 0.145f
            val baseY = cy + leafScale * 0.34f
            val path = Path().apply {
                moveTo(cx, baseY)
                cubicTo(
                    cx - halfWidth,
                    baseY - length * 0.24f,
                    cx - halfWidth * 0.72f,
                    baseY - length * 0.72f,
                    cx,
                    baseY - length,
                )
                cubicTo(
                    cx + halfWidth * 0.72f,
                    baseY - length * 0.72f,
                    cx + halfWidth,
                    baseY - length * 0.24f,
                    cx,
                    baseY,
                )
                close()
            }
            canvas.drawPath(path, leafPaint)
            canvas.drawLine(cx, baseY, cx, baseY - length * 0.92f, veinPaint)
            canvas.restore()
        }

        veinPaint.strokeWidth = 1.4f * density
        canvas.drawLine(
            cx,
            cy + leafScale * 0.15f,
            cx,
            cy + leafScale * 0.72f,
            veinPaint,
        )

        if (state == "speaking") {
            ringPaint.strokeWidth = 1.8f * density
            for (index in 0..2) {
                val waveRadius = radius * (0.48f + index * 0.16f + pulse * 0.035f)
                ringPaint.color = Color.argb(
                    135 - index * 30,
                    Color.red(primary),
                    Color.green(primary),
                    Color.blue(primary),
                )
                canvas.drawArc(
                    cx - waveRadius,
                    cy - waveRadius,
                    cx + waveRadius,
                    cy + waveRadius,
                    205f,
                    130f,
                    false,
                    ringPaint,
                )
            }
        }
    }
}
