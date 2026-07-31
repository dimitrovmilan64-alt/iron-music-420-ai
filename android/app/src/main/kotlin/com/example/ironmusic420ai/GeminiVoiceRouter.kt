package com.example.ironmusic420ai

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.io.BufferedReader
import java.io.InputStreamReader
import java.net.HttpURLConnection
import java.net.URL

/**
 * Sends a recognized Bulgarian utterance to Gemini and returns one safe,
 * allow-listed decision. The model never executes Android actions directly.
 */
class GeminiVoiceRouter(private val context: Context) {
    companion object {
        const val PREFS_NAME = "iron_ai_settings"
        const val KEY_GEMINI_API_KEY = "gemini_api_key"
        private const val KEY_ACTIVE_MODEL = "gemini_voice_active_model"
        private const val BASE_URL = "https://generativelanguage.googleapis.com/v1beta"

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
            "chrome",
            "web_search",
            "camera",
            "maps",
            "maps_search",
            "alarms",
            "calendar",
            "dialer",
            "dial_number",
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
Ти си мозъкът на Iron Music 420 AI — личен Android гласов асистент.
Потребителят говори естествено на български. Разбери намерението, без да изискваш точна команда.
Ще получаваш контекст от предишните реплики в текущия разговор. Разбирай кратки продължения като „не, другото“, „направи го по-кратко“ и „сега отвори това“ според контекста.

Върни САМО валиден JSON обект с точно тези полета:
{"action":"...","argument":"...","reply":"..."}

Позволени действия:
- reply: нормален кратък отговор на въпрос, разговор, идея, рап, обяснение или неподдържана операция.
- youtube: отвори YouTube.
- youtube_search: търси в YouTube; argument е заявката.
- chrome: отвори Chrome.
- web_search: търси в интернет; argument е заявката.
- camera: отвори камерата.
- maps: отвори картите.
- maps_search: търси място/адрес; argument е заявката.
- alarms: отвори алармите.
- calendar: отвори календара.
- dialer: отвори телефона за набиране.
- dial_number: отвори набиране с номер; argument съдържа само номера.
- bluetooth: отвори Bluetooth настройките.
- wifi: отвори Wi-Fi настройките.
- settings: отвори системните настройки.
- flash_on / flash_off: включи или изключи фенерчето.
- volume_up / volume_down: увеличи или намали медийния звук с една стъпка.
- music_mode: активирай музикалния режим.
- night_mode: намали звука за нощен режим.
- studio: отвори Rap Studio в Iron.
- chat: отвори AI чата в Iron.
- songs: отвори песните в Iron.
- home: отвори началния екран в Iron.
- automate: изпрати команда към Automate/MacroDroid; argument е само името на командата.

Правила:
1. Избирай действие само когато намерението е ясно. Иначе action=reply и задай един кратък уточняващ въпрос.
2. Не измисляй други действия и не връщай shell команди, package имена, URL адреси или код за изпълнение.
3. За обаждане само отвори набирача; никога не извършвай директно повикване.
4. За плащания, пароли, изтриване на данни, изпращане на съобщения и други чувствителни операции използвай reply и обясни кратко ограничението.
5. reply трябва да е естествен български, подходящ за произнасяне, обикновено до две изречения.
6. При действие reply е кратко потвърждение, например „Отварям YouTube.“
"""
    }

    data class Decision(
        val action: String,
        val argument: String,
        val reply: String,
    )

    class MissingApiKeyException : Exception()
    class AiUnavailableException(message: String) : Exception(message)

    private data class ConversationTurn(
        val role: String,
        val text: String,
    )

    private val preferences =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    private val conversation = mutableListOf<ConversationTurn>()

    fun hasApiKey(): Boolean = apiKey().isNotBlank()

    @Synchronized
    fun resetConversation() {
        conversation.clear()
    }

    @Synchronized
    fun route(utterance: String): Decision {
        val key = apiKey()
        if (key.isBlank()) throw MissingApiKeyException()

        val models = linkedSetOf<String>()
        preferences.getString(KEY_ACTIVE_MODEL, null)?.let(models::add)
        models.addAll(PREFERRED_MODELS)

        var lastMessage = "AI временно не отговаря."
        for (model in models) {
            val result = requestDecision(
                apiKey = key,
                model = model,
                utterance = utterance,
            )

            when {
                result.statusCode == 200 && result.body.isNotBlank() -> {
                    val decision = parseDecision(result.body)
                    rememberTurn(utterance, decision)
                    preferences.edit().putString(KEY_ACTIVE_MODEL, model).apply()
                    return decision
                }
                result.statusCode == 404 -> {
                    lastMessage = "Моделът $model не е наличен."
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

    private fun apiKey(): String =
        preferences.getString(KEY_GEMINI_API_KEY, "").orEmpty().trim()

    private data class HttpResult(
        val statusCode: Int,
        val body: String,
    )

    private fun requestDecision(
        apiKey: String,
        model: String,
        utterance: String,
    ): HttpResult {
        val url = URL("$BASE_URL/models/$model:generateContent")
        val connection = (url.openConnection() as HttpURLConnection).apply {
            requestMethod = "POST"
            connectTimeout = 15_000
            readTimeout = 45_000
            doOutput = true
            setRequestProperty("Content-Type", "application/json; charset=utf-8")
            setRequestProperty("x-goog-api-key", apiKey)
        }

        val payload = JSONObject().apply {
            put(
                "systemInstruction",
                JSONObject().put(
                    "parts",
                    JSONArray().put(JSONObject().put("text", SYSTEM_PROMPT)),
                ),
            )
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
            contents.put(
                JSONObject()
                    .put("role", "user")
                    .put(
                        "parts",
                        JSONArray().put(JSONObject().put("text", utterance)),
                    ),
            )
            put("contents", contents)
            val generationConfig = JSONObject()
                .put("maxOutputTokens", 500)
            if (!model.startsWith("gemini-3.5") &&
                !model.startsWith("gemini-3.6")
            ) {
                generationConfig.put("temperature", 0.15)
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

        val cleanJson = rawText
            .removePrefix("```json")
            .removePrefix("```")
            .removeSuffix("```")
            .trim()
        val json = JSONObject(cleanJson)
        val rawAction = json.optString("action", "reply")
            .lowercase()
            .trim()
        val action = if (rawAction in ALLOWED_ACTIONS) rawAction else "reply"
        val argument = json.optString("argument", "").trim().take(500)
        var reply = json.optString("reply", "").trim().take(1_500)

        if (action == "reply" && reply.isBlank()) {
            reply = "Не успях да формулирам отговор. Опитай пак."
        }

        return Decision(action, argument, reply)
    }

    private fun rememberTurn(utterance: String, decision: Decision) {
        val modelContext = JSONObject()
            .put("action", decision.action)
            .put("argument", decision.argument)
            .put("reply", decision.reply)
            .toString()

        conversation.add(ConversationTurn("user", utterance.trim()))
        conversation.add(ConversationTurn("model", modelContext))
        while (conversation.size > 12) {
            conversation.removeAt(0)
        }
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
