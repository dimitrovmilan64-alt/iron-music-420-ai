package com.example.ironmusic420ai

import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
import android.graphics.BlurMaskFilter
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PixelFormat
import android.graphics.RadialGradient
import android.graphics.Rect
import android.graphics.RectF
import android.graphics.Shader
import android.graphics.SweepGradient
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.provider.Settings
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.sin

class IronOrbService : Service() {
    companion object {
        const val ACTION_START = "com.example.ironmusic420ai.START_IRON_ORB"
        const val ACTION_STOP = "com.example.ironmusic420ai.STOP_IRON_ORB"
        const val PREFS = "iron_orb_preferences"
        const val KEY_ENABLED = "orb_enabled"
        private const val KEY_X = "orb_x"
        private const val KEY_Y = "orb_y"

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
    private lateinit var windowManager: WindowManager
    private var orbView: IronOrbView? = null
    private var layoutParams: WindowManager.LayoutParams? = null
    private var visualState = "idle"
    private var lastTick = 0L
    private var dragOriginX = 0
    private var dragOriginY = 0

    private val animateRunnable = object : Runnable {
        override fun run() {
            val view = orbView ?: return
            val now = android.os.SystemClock.elapsedRealtime()
            val deltaSeconds = if (lastTick == 0L) {
                0.033f
            } else {
                (now - lastTick).coerceIn(12L, 80L) / 1000f
            }
            lastTick = now
            view.advance(deltaSeconds, visualState)
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
        handler.removeCallbacks(animateRunnable)
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
        val size = dp(118)
        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }
        val prefs = getSharedPreferences(PREFS, Context.MODE_PRIVATE)
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
            x = prefs.getInt(KEY_X, dp(24))
            y = prefs.getInt(KEY_Y, dp(180))
        }

        val view = IronOrbView(
            context = this,
            onDragStart = {
                dragOriginX = params.x
                dragOriginY = params.y
            },
            onDrag = { deltaX, deltaY -> moveOrb(deltaX, deltaY) },
            onDragEnd = { saveOrbPosition() },
        ).apply {
            contentDescription = "Живата сфера на Hey Iron"
            setOnClickListener { openConversation() }
        }
        windowManager.addView(view, params)
        orbView = view
        layoutParams = params
        clampOrbToScreen()
        lastTick = 0L
        handler.removeCallbacks(animateRunnable)
        handler.post(animateRunnable)
    }

    private fun moveOrb(deltaX: Float, deltaY: Float) {
        val view = orbView ?: return
        val params = layoutParams ?: return
        val bounds = screenBounds()
        val maxX = (bounds.first - view.width).coerceAtLeast(0)
        val minY = dp(24)
        val maxY = (bounds.second - view.height - dp(72)).coerceAtLeast(minY)
        params.x = (dragOriginX + deltaX.toInt()).coerceIn(0, maxX)
        params.y = (dragOriginY + deltaY.toInt()).coerceIn(minY, maxY)
        try {
            windowManager.updateViewLayout(view, params)
        } catch (_: Exception) {
            // Ignore a drag frame if Android is detaching the overlay.
        }
    }

    private fun clampOrbToScreen() {
        val view = orbView ?: return
        val params = layoutParams ?: return
        view.post {
            val bounds = screenBounds()
            val maxX = (bounds.first - view.width).coerceAtLeast(0)
            val minY = dp(24)
            val maxY = (bounds.second - view.height - dp(72)).coerceAtLeast(minY)
            params.x = params.x.coerceIn(0, maxX)
            params.y = params.y.coerceIn(minY, maxY)
            try {
                windowManager.updateViewLayout(view, params)
            } catch (_: Exception) {
                return@post
            }
        }
    }

    private fun saveOrbPosition() {
        val params = layoutParams ?: return
        getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putInt(KEY_X, params.x)
            .putInt(KEY_Y, params.y)
            .apply()
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
}

private class IronOrbView(
    context: Context,
    private val onDragStart: () -> Unit,
    private val onDrag: (Float, Float) -> Unit,
    private val onDragEnd: () -> Unit,
) : View(context) {
    private val density = resources.displayMetrics.density
    private val shellPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val glowPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val ringPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeCap = Paint.Cap.ROUND
    }
    private val leafPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.FILL
    }
    private val leafGlowPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.FILL
        maskFilter = BlurMaskFilter(7f * density, BlurMaskFilter.Blur.NORMAL)
    }
    private val leafOutlinePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeJoin = Paint.Join.ROUND
    }
    private val veinPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeCap = Paint.Cap.ROUND
    }
    private val particlePaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val exactLeafPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        isFilterBitmap = true
        isDither = true
    }
    private val exactCoreBitmap = runCatching {
        context.assets.open("flutter_assets/assets/images/hud_core_exact.png").use {
            BitmapFactory.decodeStream(it)
        }
    }.getOrNull()
    private var phase = 0f
    private var state = "idle"
    private var downX = 0f
    private var downY = 0f
    private var dragging = false

    init {
        setLayerType(LAYER_TYPE_SOFTWARE, null)
    }

    fun setVisualState(value: String) {
        state = value
        invalidate()
    }

    fun advance(deltaSeconds: Float, value: String) {
        state = value
        val pace = when (state) {
            "listening" -> 2.7f
            "thinking" -> 3.6f
            "speaking" -> 4.4f
            else -> 1.45f
        }
        phase = (phase + deltaSeconds * pace) % 6.2831855f
        invalidate()
    }

    override fun onTouchEvent(event: MotionEvent): Boolean {
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                downX = event.rawX
                downY = event.rawY
                dragging = false
                onDragStart()
                animate().scaleX(0.95f).scaleY(0.95f).setDuration(80L).start()
                return true
            }
            MotionEvent.ACTION_MOVE -> {
                val deltaX = event.rawX - downX
                val deltaY = event.rawY - downY
                if (!dragging && hypot(deltaX.toDouble(), deltaY.toDouble()) > 7f * density) {
                    dragging = true
                }
                if (dragging) onDrag(deltaX, deltaY)
                return true
            }
            MotionEvent.ACTION_UP -> {
                animate().scaleX(1f).scaleY(1f).setDuration(130L).start()
                if (dragging) onDragEnd() else performClick()
                dragging = false
                return true
            }
            MotionEvent.ACTION_CANCEL -> {
                animate().scaleX(1f).scaleY(1f).setDuration(130L).start()
                if (dragging) onDragEnd()
                dragging = false
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
        val radius = min(width, height) * 0.405f
        val pulse = 0.5f + 0.5f * sin(phase)
        val slowWave = sin(phase * 0.47f)
        val innerY = cy + slowWave * 1.7f * density
        val primary = when (state) {
            "listening" -> Color.rgb(55, 226, 255)
            "thinking" -> Color.rgb(255, 190, 45)
            "speaking" -> Color.rgb(82, 255, 137)
            else -> Color.rgb(0, 255, 112)
        }

        drawOuterGlow(canvas, cx, cy, radius, pulse, primary)
        drawGlassSphere(canvas, cx, innerY, radius, pulse, slowWave, primary)
        drawFullOrbitLines(canvas, cx, innerY, radius, pulse, primary)
        drawParticles(canvas, cx, innerY, radius, pulse, primary)
        drawExactLeaf(canvas, cx, innerY, radius, pulse, slowWave)
        drawGlassHighlight(canvas, cx, innerY, radius, pulse)
        if (state == "speaking") {
            drawSpeakingWaves(canvas, cx, innerY, radius, pulse, primary)
        }
    }

    private fun drawOuterGlow(canvas: Canvas, cx: Float, cy: Float, radius: Float, pulse: Float, primary: Int) {
        glowPaint.shader = RadialGradient(
            cx, cy, radius * 1.38f,
            intArrayOf(
                Color.TRANSPARENT,
                Color.argb((40 + pulse * 35).toInt(), Color.red(primary), Color.green(primary), Color.blue(primary)),
                Color.TRANSPARENT,
            ),
            floatArrayOf(0.48f, 0.76f, 1f),
            Shader.TileMode.CLAMP,
        )
        canvas.drawCircle(cx, cy, radius * 1.38f, glowPaint)
        glowPaint.shader = null
    }

    private fun drawGlassSphere(
        canvas: Canvas,
        cx: Float,
        cy: Float,
        radius: Float,
        pulse: Float,
        slowWave: Float,
        primary: Int,
    ) {
        shellPaint.shader = RadialGradient(
            cx - radius * (0.34f + slowWave * 0.035f),
            cy - radius * 0.38f,
            radius * 1.42f,
            intArrayOf(
                Color.argb(238, 14, 65, 38),
                Color.argb(236, 3, 30, 17),
                Color.argb(222, 0, 14, 9),
                Color.argb(65, Color.red(primary), Color.green(primary), Color.blue(primary)),
                Color.TRANSPARENT,
            ),
            floatArrayOf(0f, 0.27f, 0.62f, 0.84f, 1f),
            Shader.TileMode.CLAMP,
        )
        canvas.drawCircle(cx, cy, radius * (1f + pulse * 0.018f), shellPaint)
        shellPaint.shader = null

        ringPaint.shader = SweepGradient(
            cx,
            cy,
            intArrayOf(
                Color.argb(35, 0, 255, 112),
                Color.argb(245, 120, 255, 171),
                Color.argb(70, 0, 255, 112),
                Color.argb(215, 0, 180, 76),
                Color.argb(35, 0, 255, 112),
            ),
            null,
        )
        ringPaint.strokeWidth = 1.45f * density
        canvas.drawCircle(cx, cy, radius * 0.99f, ringPaint)
        ringPaint.shader = null
    }

    private fun drawFullOrbitLines(canvas: Canvas, cx: Float, cy: Float, radius: Float, pulse: Float, primary: Int) {
        canvas.save()
        canvas.rotate(sin(phase * 0.35f) * 2.8f, cx, cy)
        ringPaint.strokeWidth = 0.78f * density
        for (index in 0..2) {
            val orbitRadius = radius * (0.62f + index * 0.13f)
            val flatten = 0.47f + index * 0.105f + pulse * 0.012f
            ringPaint.color = Color.argb(
                88 + index * 18,
                Color.red(primary),
                Color.green(primary),
                Color.blue(primary),
            )
            canvas.drawOval(
                RectF(
                    cx - orbitRadius,
                    cy - orbitRadius * flatten,
                    cx + orbitRadius,
                    cy + orbitRadius * flatten,
                ),
                ringPaint,
            )
        }
        canvas.restore()
    }

    private fun drawParticles(canvas: Canvas, cx: Float, cy: Float, radius: Float, pulse: Float, primary: Int) {
        particlePaint.color = Color.argb((85 + pulse * 75).toInt(), Color.red(primary), Color.green(primary), Color.blue(primary))
        for (index in 0 until 13) {
            val angle = phase * (0.86f + index * 0.018f) + index * 2.39996f
            val orbit = radius * (0.55f + (index % 4) * 0.085f)
            val px = cx + cos(angle) * orbit
            val py = cy + sin(angle) * orbit * 0.72f
            canvas.drawCircle(px, py, (0.5f + index % 3 * 0.28f) * density, particlePaint)
        }
    }

    private fun serratedLeaflet(length: Float, halfWidth: Float, teeth: Int): Path {
        val path = Path().apply { moveTo(0f, 0f) }
        val steps = teeth * 2 + 2
        for (index in 1 until steps) {
            val t = index.toFloat() / steps
            val envelope = sin(Math.PI * t).pow(0.72).toFloat()
            val serration = if (index % 2 == 0) 1f else 0.58f
            path.lineTo(-halfWidth * envelope * serration, -length * t)
        }
        path.lineTo(0f, -length)
        for (index in steps - 1 downTo 1) {
            val t = index.toFloat() / steps
            val envelope = sin(Math.PI * t).pow(0.72).toFloat()
            val serration = if (index % 2 == 0) 1f else 0.58f
            path.lineTo(halfWidth * envelope * serration, -length * t)
        }
        return path.apply { close() }
    }

    private fun drawExactLeaf(canvas: Canvas, cx: Float, cy: Float, radius: Float, pulse: Float, slowWave: Float) {
        val bitmap = exactCoreBitmap
        if (bitmap != null) {
            val source = Rect(
                (bitmap.width * 0.205f).toInt(),
                (bitmap.height * 0.185f).toInt(),
                (bitmap.width * 0.805f).toInt(),
                (bitmap.height * 0.865f).toInt(),
            )
            val leafWidth = radius * (1.48f + pulse * 0.018f)
            val leafHeight = radius * (1.60f + pulse * 0.020f)
            val destination = RectF(
                cx - leafWidth / 2f,
                cy - leafHeight * 0.57f,
                cx + leafWidth / 2f,
                cy + leafHeight * 0.43f,
            )
            exactLeafPaint.alpha = (238 + pulse * 17).toInt().coerceIn(0, 255)
            canvas.save()
            canvas.rotate(slowWave * 1.7f, cx, cy + radius * 0.30f)
            canvas.scale(0.985f + slowWave * 0.012f, 1f, cx, cy)
            canvas.drawBitmap(bitmap, source, destination, exactLeafPaint)
            canvas.restore()
            return
        }

        // These are the same seven leaflet proportions used by
        // _CannabisLeafPainter in the main Iron sphere.
        val scale = radius * (1.20f + pulse * 0.020f)
        val baseY = cy + scale * 0.31f
        val angles = floatArrayOf(-55.00f, -36.67f, -18.91f, 0f, 18.91f, 36.67f, 55.00f)
        val lengths = floatArrayOf(0.39f, 0.56f, 0.72f, 0.86f, 0.72f, 0.56f, 0.39f)
        val widths = floatArrayOf(0.050f, 0.068f, 0.082f, 0.090f, 0.082f, 0.068f, 0.050f)
        val teeth = intArrayOf(3, 4, 5, 6, 5, 4, 3)

        canvas.save()
        canvas.rotate(slowWave * 2.1f, cx, baseY)
        canvas.scale(0.97f + slowWave * 0.018f, 1f, cx, baseY)
        for (index in angles.indices) {
            canvas.save()
            canvas.translate(cx, baseY)
            canvas.rotate(angles[index])
            val length = scale * lengths[index]
            val halfWidth = scale * widths[index]
            val path = serratedLeaflet(length, halfWidth, teeth[index])

            leafGlowPaint.color = Color.argb((90 + pulse * 75).toInt(), 0, 255, 106)
            canvas.drawPath(path, leafGlowPaint)
            leafPaint.shader = LinearGradient(
                -halfWidth,
                0f,
                halfWidth,
                -length,
                intArrayOf(
                    Color.rgb(0, 77, 31),
                    Color.rgb(0, 205, 82),
                    Color.rgb(82, 255, 145),
                    Color.rgb(9, 117, 48),
                ),
                floatArrayOf(0f, 0.38f, 0.69f, 1f),
                Shader.TileMode.CLAMP,
            )
            canvas.drawPath(path, leafPaint)
            leafPaint.shader = null

            leafOutlinePaint.color = Color.argb(238, 154, 255, 190)
            leafOutlinePaint.strokeWidth = max(0.65f * density, scale * 0.010f)
            canvas.drawPath(path, leafOutlinePaint)

            veinPaint.color = Color.argb((155 + pulse * 80).toInt(), 196, 255, 217)
            veinPaint.strokeWidth = max(0.48f * density, scale * 0.0054f)
            canvas.drawLine(0f, 0f, 0f, -length * 0.96f, veinPaint)
            for (tooth in 1..teeth[index]) {
                val t = tooth.toFloat() / (teeth[index] + 1)
                val envelope = sin(Math.PI * t).pow(0.72).toFloat()
                val x = halfWidth * envelope * 0.78f
                val y = -length * t
                canvas.drawLine(0f, y + length * 0.03f, -x, y - length * 0.025f, veinPaint)
                canvas.drawLine(0f, y + length * 0.03f, x, y - length * 0.025f, veinPaint)
            }
            canvas.restore()
        }

        veinPaint.color = Color.argb(235, 92, 255, 145)
        veinPaint.strokeWidth = max(1.15f * density, scale * 0.014f)
        canvas.drawLine(cx, baseY - scale * 0.03f, cx, baseY + scale * 0.27f, veinPaint)
        canvas.restore()
    }

    private fun drawGlassHighlight(canvas: Canvas, cx: Float, cy: Float, radius: Float, pulse: Float) {
        shellPaint.shader = RadialGradient(
            cx - radius * 0.38f,
            cy - radius * 0.42f,
            radius * 0.62f,
            intArrayOf(Color.argb(100, 225, 255, 236), Color.argb(25, 80, 255, 153), Color.TRANSPARENT),
            floatArrayOf(0f, 0.32f, 1f),
            Shader.TileMode.CLAMP,
        )
        canvas.drawCircle(cx - radius * 0.23f, cy - radius * 0.26f, radius * (0.42f + pulse * 0.01f), shellPaint)
        shellPaint.shader = null
    }

    private fun drawSpeakingWaves(canvas: Canvas, cx: Float, cy: Float, radius: Float, pulse: Float, primary: Int) {
        ringPaint.strokeWidth = 1.65f * density
        for (index in 0..2) {
            val waveRadius = radius * (0.55f + index * 0.16f + pulse * 0.025f)
            ringPaint.color = Color.argb(130 - index * 29, Color.red(primary), Color.green(primary), Color.blue(primary))
            canvas.drawArc(cx - waveRadius, cy - waveRadius, cx + waveRadius, cy + waveRadius, 205f, 130f, false, ringPaint)
        }
    }
}
