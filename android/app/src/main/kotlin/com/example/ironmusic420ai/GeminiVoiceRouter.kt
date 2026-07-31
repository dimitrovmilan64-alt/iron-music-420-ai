package com.example.ironmusic420ai

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.io.BufferedReader
import java.io.InputStreamReader
import java.net.HttpURLConnection
import java.net.URL
import java.util.ArrayDeque

/**
 * Routes natural Bulgarian speech through Gemini and returns only an
 * allow-listed decision. Conversation memory is kept in RAM while the
 * foreground voice service is alive.
 */
class GeminiVoiceRouter(private val context: Context) {
    companion object {
        const val PREFS_NAME = "iron_ai_settings"
        const val KEY_GEMINI_API_KEY = "gemini_api_key"
        private const val KEY_ACTIVE_MODEL = "gemini_voice_active_model"
        private const val BASE_URL = "https://generativelanguage.googleapis.com/v1beta"
        private const val MAX_HISTORY_ITEMS = 16

        private val PREFERRED_MODELS = listOf(
            "gemini-3.6-flash",
            "gemini-3.5-flash",
            "gemini-3.5-flash-lite",
            "gemini-3.1-flash-lite",
            "gemini-2.5-flash",
            "gemini-flash-latest",
        )

        val ALLOWED_ACTIONS = setOf(
            "reply",
            "youtube",
            "youtube_search",
            "spotify",
            "spotify_search",
            "chrome",
            "web_search",
            "camera",
            "gallery",
            "maps",
            "maps_search",
            "alarms",
            "set_alarm",
            "set_timer",
            "calendar",
            "dialer",
            "dial_number",
            "contacts",
            "email",
            "messages",
            "calculator",
            "play_store",
            "bluetooth",
            "wifi",
            "settings",
            "flash_on",
            "flash_off",
            "volume_up",
            "volume_down",
            "music_mode",
            "night_mode",
            "studio",
            "chat",
            "songs",
            "home",
            "automate",
        )

        private const val SYSTEM_PROMPT = """
Ти си Iron Music 420 AI — естествен български личен асистент и събеседник.
Говори като умен човек, а не като меню с команди. Следи контекста от предишните реплики.
Потребителят може да говори разговорно, с грешки и недовършени изречения.

Върни САМО валиден JSON обект:
{"action":"...","argument":"...","reply":"..."}

Позволени действия:
- reply: нормален разговор, отговор, идея, обяснение, помощ, музика или уточняващ въпрос.
- youtube / youtube_search: отвори YouTube или търси; argument е заявката.
- spotify / spotify_search: отвори Spotify или търси музика; argument е заявката.
- chrome / web_search: отвори браузъра или търси; argument е заявката.
- camera / gallery: отвори камерата или снимките.
- maps / maps_search: отвори карти или търси място; argument е заявката.
- alarms: отвори алармите.
- set_alarm: създай аларма; argument е HH:MM|име, например 07:30|Ставане.
- set_timer: стартирай таймер; argument е секунди|име, например 600|Чай.
- calendar: отвори календара.
- dialer / dial_number: отвори набирача; при dial_number argument съдържа само номер.
- contacts: отвори контактите.
- email: отвори приложение за имейл.
- messages: отвори приложението за съобщения, без автоматично изпращане.
- calculator: отвори калкулатора.
- play_store: търси приложение; argument е името.
- bluetooth / wifi / settings: отвори съответните настройки.
- flash_on / flash_off: фенерче.
- volume_up / volume_down: една стъпка на медийния звук.
- music_mode / night_mode: локален режим.
- studio / chat / songs / home: отвори секция в Iron.
- automate: изпрати allow-listed име към Automate/MacroDroid; argument е името.

Правила:
1. Избирай действие само когато намерението е ясно. При неяснота използвай reply и задай кратък въпрос.
2. Никога не връщай произволен код, shell команда, package име или URL.
3. Не изпращай съобщения, имейли, плащания и не започвай обаждане автоматично.
4. За чувствителни или неподдържани операции използвай reply и обясни ограничението.
5. При разговор reply може да е естествен отговор от две до пет изречения. Не бъди телеграфен.
6. При действие reply е кратко и ясно потвърждение.
7. Когато потребителят каже „а сега“, „това“, „същото“ или друга препратка, използвай историята.
"""
    }

    data class Decision(
        val action: String,
        val argument: String,
        val reply: String,
    )

    private data class Turn(
        val role: String,
        val text: String,
    )

    class MissingApiKeyException : Exception()
    class AiUnavailableException(message: String) : Exception(message)

    private val preferences =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    private val history = ArrayDeque<Turn>()

    fun hasApiKey(): Boolean = apiKey().isNotBlank()

    @Synchronized
    fun clearConversation() {
        history.clear()
    }

    @Synchronized
    fun route(utterance: String): Decision {
        val key = apiKey()
        if (key.isBlank()) throw MissingApiKeyException()

        val conversation = history.toList() + Turn("user", utterance)
        val models = linkedSetOf<String>()
        preferences.getString(KEY_ACTIVE_MODEL, null)?.let(models::add)
        models.addAll(PREFERRED_MODELS)

        var lastMessage = "AI временно не отговаря."
        for (model in models) {
            val result = requestDecision(
                apiKey = key,
                model = model,
                conversation = conversation,
            )

            when {
                result.statusCode == 200 && result.body.isNotBlank() -> {
                    val decision = parseDecision(result.body)
                    preferences.edit().putString(KEY_ACTIVE_MODEL, model).apply()
                    remember(
                        userText = utterance,
                        decision = decision,
                    )
                    return decision
                }
                result.statusCode == 404 -> {
                    lastMessage = "Избраният AI модел не е наличен."
                    continue
                }
                result.statusCode == 401 || result.statusCode == 403 -> {
                    throw AiUnavailableException(
                        "Gemini API ключът не е валиден или няма разрешение.",
                    )
                }
                result.statusCode == 429 -> {
                    throw AiUnavailableException(
                        "Достигнат е лимитът на AI услугата. Опитай след малко.",
                    )
                }
                result.statusCode in 500..599 -> {
                    lastMessage = "AI услугата временно не отговаря."
                    continue
                }
                else -> {
                    lastMessage = extractError(result.body)
                    break
                }
            }
        }

        throw AiUnavailableException(lastMessage)
    }

    private fun remember(userText: String, decision: Decision) {
        history.addLast(Turn("user", userText))
        val modelText = buildString {
            append(decision.reply)
            if (decision.action != "reply") {
                append(" [изпълнено действие: ")
                append(decision.action)
                if (decision.argument.isNotBlank()) {
                    append(", аргумент: ")
                    append(decision.argument.take(180))
                }
                append("]")
            }
        }
        history.addLast(Turn("model", modelText))

        while (history.size > MAX_HISTORY_ITEMS) {
            history.removeFirst()
        }
    }

    private fun apiKey(): String =
        preferences.getString(KEY_GEMINI_API_KEY, "").orEmpty().trim()

    private data class HttpResult(
        val statusCode: Int,
        val body: String,
    )

    private fun requestDecision(
        apiKey: String,
        model: String,
        conversation: List<Turn>,
    ): HttpResult {
        val url = URL("$BASE_URL/models/$model:generateContent")
        val connection = (url.openConnection() as HttpURLConnection).apply {
            requestMethod = "POST"
            connectTimeout = 15_000
            readTimeout = 55_000
            doOutput = true
            setRequestProperty("Content-Type", "application/json; charset=utf-8")
            setRequestProperty("x-goog-api-key", apiKey)
        }

        val contents = JSONArray()
        conversation.forEach { turn ->
            contents.put(
                JSONObject()
                    .put("role", turn.role)
                    .put(
                        "parts",
                        JSONArray().put(JSONObject().put("text", turn.text)),
                    ),
            )
        }

        val payload = JSONObject().apply {
            put(
                "systemInstruction",
                JSONObject().put(
                    "parts",
                    JSONArray().put(JSONObject().put("text", SYSTEM_PROMPT)),
                ),
            )
            put("contents", contents)
            val generationConfig = JSONObject()
                .put("maxOutputTokens", 1_200)
            if (!model.startsWith("gemini-3.5") &&
                !model.startsWith("gemini-3.6")
            ) {
                generationConfig.put("temperature", 0.35)
                generationConfig.put("topP", 0.92)
            }
            put("generationConfig", generationConfig)
        }

        return try {
            connection.outputStream.use { output ->
                output.write(payload.toString().toByteArray(Charsets.UTF_8))
            }

            val status = connection.responseCode
            val stream = if (status in 200..299) {
                connection.inputStream
            } else {
                connection.errorStream
            }
            val body = stream?.use { input ->
                BufferedReader(InputStreamReader(input, Charsets.UTF_8)).readText()
            }.orEmpty()
            HttpResult(status, body)
        } catch (error: Exception) {
            throw AiUnavailableException(
                error.localizedMessage ?: "Няма връзка с AI услугата.",
            )
        } finally {
            connection.disconnect()
        }
    }

    private fun parseDecision(responseBody: String): Decision {
        val envelope = JSONObject(responseBody)
        val candidates = envelope.optJSONArray("candidates")
            ?: throw AiUnavailableException("AI върна празен отговор.")
        val candidate = candidates.optJSONObject(0)
            ?: throw AiUnavailableException("AI върна невалиден отговор.")
        val parts = candidate
            .optJSONObject("content")
            ?.optJSONArray("parts")
            ?: throw AiUnavailableException("AI отговорът няма съдържание.")

        val rawText = buildString {
            for (index in 0 until parts.length()) {
                val text = parts.optJSONObject(index)?.optString("text").orEmpty()
                if (text.isNotBlank()) append(text)
            }
        }.trim()

        if (rawText.isBlank()) {
            throw AiUnavailableException("AI върна празен отговор.")
        }

        val firstBrace = rawText.indexOf('{')
        val lastBrace = rawText.lastIndexOf('}')
        if (firstBrace < 0 || lastBrace <= firstBrace) {
            throw AiUnavailableException("AI върна невалиден формат.")
        }

        val json = JSONObject(rawText.substring(firstBrace, lastBrace + 1))
        val rawAction = json.optString("action", "reply")
            .lowercase()
            .trim()
        val action = if (rawAction in ALLOWED_ACTIONS) rawAction else "reply"
        val argument = json.optString("argument", "").trim().take(600)
        var reply = json.optString("reply", "").trim().take(3_500)

        if (reply.isBlank()) {
            reply = if (action == "reply") {
                "Не успях да формулирам отговор. Кажи го по друг начин."
            } else {
                "Готово."
            }
        }

        return Decision(action, argument, reply)
    }

    private fun extractError(body: String): String {
        return try {
            val error = JSONObject(body).optJSONObject("error")
            error?.optString("message")
                ?.replace(Regex("\\s+"), " ")
                ?.trim()
                ?.take(240)
                .orEmpty()
                .ifBlank { "AI заявката беше отхвърлена." }
        } catch (_: Exception) {
            "AI заявката беше отхвърлена."
        }
    }
}
