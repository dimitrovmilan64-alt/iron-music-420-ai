package com.example.ironmusic420ai

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.content.ComponentName
import android.content.Context
import android.graphics.Rect
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityManager
import android.view.accessibility.AccessibilityNodeInfo

class YoutubeAutoPlayAccessibilityService : AccessibilityService() {
    companion object {
        private const val YOUTUBE_PACKAGE = "com.google.android.youtube"
        private const val PREFS_NAME = "youtube_auto_play"
        private const val KEY_PENDING_QUERY = "pending_query"
        private const val KEY_PENDING_UNTIL = "pending_until"
        private const val REQUEST_LIFETIME_MS = 15_000L
        private const val LOG_TAG = "IronYoutubeAutoPlay"

        fun isEnabled(context: Context): Boolean {
            val manager = context.getSystemService(Context.ACCESSIBILITY_SERVICE)
                as AccessibilityManager
            val component = ComponentName(
                context,
                YoutubeAutoPlayAccessibilityService::class.java,
            )
            return manager
                .getEnabledAccessibilityServiceList(
                    AccessibilityServiceInfo.FEEDBACK_ALL_MASK,
                )
                .any { service ->
                    val info = service.resolveInfo?.serviceInfo
                    info?.packageName == component.packageName &&
                        info.name == component.className
                }
        }

        fun arm(context: Context, query: String): Boolean {
            val cleanQuery = query.trim()
            if (cleanQuery.isBlank() || !isEnabled(context)) {
                clearPending(context)
                return false
            }
            context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .edit()
                .putString(KEY_PENDING_QUERY, cleanQuery)
                .putLong(
                    KEY_PENDING_UNTIL,
                    System.currentTimeMillis() + REQUEST_LIFETIME_MS,
                )
                .apply()
            Log.i(LOG_TAG, "request_armed queryLength=${cleanQuery.length}")
            return true
        }

        fun clearPending(context: Context) {
            context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .edit()
                .remove(KEY_PENDING_QUERY)
                .remove(KEY_PENDING_UNTIL)
                .apply()
        }
    }

    private data class PendingRequest(
        val query: String,
        val deadline: Long,
    )

    private data class ClickCandidate(
        val node: AccessibilityNodeInfo,
        val score: Int,
        val top: Int,
    )

    private val handler = Handler(Looper.getMainLooper())
    private var attemptScheduled = false
    private val tryPlayback = Runnable {
        attemptScheduled = false
        attemptPendingPlayback()
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        Log.i(LOG_TAG, "service_connected build=50")
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event?.packageName?.toString() != YOUTUBE_PACKAGE) return
        if (loadPendingRequest() == null) return
        scheduleAttempt(120L)
    }

    override fun onInterrupt() {
        handler.removeCallbacks(tryPlayback)
        attemptScheduled = false
    }

    override fun onUnbind(intent: android.content.Intent?): Boolean {
        handler.removeCallbacks(tryPlayback)
        attemptScheduled = false
        return super.onUnbind(intent)
    }

    private fun scheduleAttempt(delayMillis: Long) {
        if (attemptScheduled) return
        attemptScheduled = true
        handler.postDelayed(tryPlayback, delayMillis)
    }

    private fun loadPendingRequest(): PendingRequest? {
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val query = prefs.getString(KEY_PENDING_QUERY, null).orEmpty().trim()
        val deadline = prefs.getLong(KEY_PENDING_UNTIL, 0L)
        if (query.isBlank() || deadline <= System.currentTimeMillis()) {
            if (query.isNotBlank() || deadline != 0L) clearPending(this)
            return null
        }
        return PendingRequest(query, deadline)
    }

    private fun attemptPendingPlayback() {
        val request = loadPendingRequest() ?: return
        val root = rootInActiveWindow
        if (root == null || root.packageName?.toString() != YOUTUBE_PACKAGE) {
            retryBeforeDeadline(request)
            return
        }
        if (!hasMatchingSearchField(root, request.query)) {
            retryBeforeDeadline(request)
            return
        }

        val candidate = findBestCandidate(root, request.query)
        if (
            candidate != null &&
            candidate.node.performAction(AccessibilityNodeInfo.ACTION_CLICK)
        ) {
            clearPending(this)
            handler.removeCallbacks(tryPlayback)
            attemptScheduled = false
            Log.i(LOG_TAG, "result_clicked score=${candidate.score}")
            return
        }
        retryBeforeDeadline(request)
    }

    private fun retryBeforeDeadline(request: PendingRequest) {
        if (System.currentTimeMillis() >= request.deadline) {
            clearPending(this)
            Log.i(LOG_TAG, "request_expired")
            return
        }
        scheduleAttempt(350L)
    }

    private fun hasMatchingSearchField(
        root: AccessibilityNodeInfo,
        query: String,
    ): Boolean {
        traverse(root) { node ->
            val viewId = node.viewIdResourceName.orEmpty().lowercase()
            val className = node.className?.toString().orEmpty()
            val isSearchField = node.isEditable ||
                className.endsWith("EditText") ||
                viewId.contains("search_edit_text") ||
                viewId.contains("search_box")
            if (!isSearchField) return@traverse false
            YoutubeResultMatcher.isSearchFieldFor(
                query = query,
                fieldText = collectSubtreeText(node),
            )
        }.let { return it }
    }

    private fun findBestCandidate(
        root: AccessibilityNodeInfo,
        query: String,
    ): ClickCandidate? {
        val rootBounds = Rect().also(root::getBoundsInScreen)
        val toolbarLimit = rootBounds.top + (rootBounds.height() * 0.12f).toInt()
        var best: ClickCandidate? = null
        val queue = ArrayDeque<AccessibilityNodeInfo>()
        queue.add(root)
        var visited = 0

        while (queue.isNotEmpty() && visited < 1_000) {
            val node = queue.removeFirst()
            visited++
            if (node.isVisibleToUser && node.isEnabled && node.isClickable) {
                val bounds = Rect().also(node::getBoundsInScreen)
                val editable = containsEditableNode(node)
                val candidateText = collectSubtreeText(node)
                val score = YoutubeResultMatcher.score(
                    query = query,
                    candidateText = candidateText,
                    editable = editable,
                )
                val resultScore = if (score == Int.MIN_VALUE) 0 else score
                if (
                    YoutubeResultMatcher.isEligibleMediaResult(
                        candidateText = candidateText,
                        editable = editable,
                    ) &&
                    bounds.height() >= 48 &&
                    bounds.bottom > toolbarLimit
                ) {
                    val candidate = ClickCandidate(node, resultScore, bounds.top)
                    if (
                        best == null ||
                        candidate.score > best.score ||
                        (candidate.score == best.score && candidate.top < best.top)
                    ) {
                        best = candidate
                    }
                }
            }
            for (index in 0 until node.childCount) {
                node.getChild(index)?.let(queue::addLast)
            }
        }
        return best
    }

    private fun containsEditableNode(root: AccessibilityNodeInfo): Boolean =
        traverse(root) { node ->
            node.isEditable ||
                node.className?.toString().orEmpty().endsWith("EditText")
        }

    private fun collectSubtreeText(root: AccessibilityNodeInfo): String {
        val parts = LinkedHashSet<String>()
        val queue = ArrayDeque<Pair<AccessibilityNodeInfo, Int>>()
        queue.add(root to 0)
        var visited = 0
        while (queue.isNotEmpty() && visited < 80) {
            val (node, depth) = queue.removeFirst()
            visited++
            nodeText(node).trim().takeIf(String::isNotEmpty)?.let(parts::add)
            if (depth >= 5) continue
            for (index in 0 until node.childCount) {
                node.getChild(index)?.let { child ->
                    queue.addLast(child to depth + 1)
                }
            }
        }
        return parts.joinToString(" ")
    }

    private fun nodeText(node: AccessibilityNodeInfo): String =
        listOfNotNull(node.text, node.contentDescription)
            .joinToString(" ")

    private fun traverse(
        root: AccessibilityNodeInfo,
        predicate: (AccessibilityNodeInfo) -> Boolean,
    ): Boolean {
        val queue = ArrayDeque<AccessibilityNodeInfo>()
        queue.add(root)
        var visited = 0
        while (queue.isNotEmpty() && visited < 1_000) {
            val node = queue.removeFirst()
            visited++
            if (predicate(node)) return true
            for (index in 0 until node.childCount) {
                node.getChild(index)?.let(queue::addLast)
            }
        }
        return false
    }
}
