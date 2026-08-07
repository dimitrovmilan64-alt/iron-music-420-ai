package com.example.ironmusic420ai

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.io.BufferedReader
import java.io.InputStreamReader
import java.net.HttpURLConnection
import java.net.URL

/**
 * Routes a recognized Bulgarian utterance through Gemini, then through an
 * OpenAI-compatible backup provider. The model only returns allow-listed
 * decisions and never executes Android actions directly.
 */
class GeminiVoiceRouter(private val context: Context) {
    companion object {
        const val PREFS_NAME = "iron_ai_settings"
        const val KEY_GEMINI_API_KEY = "gemini_api_key"
        const val KEY_BACKUP_API_KEY = "backup_api_key"
        const val KEY_BACKUP_BASE_URL = "backup_base_url"
        const val KEY_BACKUP_MODEL = "backup_model"
        const val DEFAULT_BACKUP_BASE_URL = "https://api.groq.com/openai/v1"
        const val DEFAULT_BACKUP_MODEL = "openai/gpt-oss-20b"

        private const val KEY_ACTIVE_MODEL = "gemini_voice_active_model"
        private const val GEMINI_BASE_URL =
            "https://generativelanguage.googleapis.com/v1beta"

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

    private data class HttpResult(
        val statusCode: Int,
        val body: String,
    )

    private val preferences =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    private val conversation = mutableListOf<ConversationTurn>()

    fun hasApiKey(): Boolean =
        geminiApiKey().isNotBlank() || backupApiKey().isNotBlank()

    @Synchronized
    fun resetConversation() {
        conversation.clear()
    }

    @Synchronized
    fun route(utterance: String): Decision {
        val geminiKey = geminiApiKey()
        val backupKey = backupApiKey()
        if (geminiKey.isBlank() && backupKey.isBlank()) {
            throw MissingApiKeyException()
        }

        val errors = mutableListOf<String>()

        if (geminiKey.isNotBlank()) {
            try {
                return routeGemini(geminiKey, utterance)
            } catch (error: AiUnavailableException) {
                errors.add(error.message.orEmpty())
            }
        }

        if (backupKey.isNotBlank()) {
            try {
                return routeBackup(backupKey, utterance)
            } catch (error: AiUnavailableException) {
                errors.add(error.message.orEmpty())
            }
        }

        val cleanErrors = errors
            .map { it.trim() }
            .filter { it.isNotBlank() }
            .distinct()
        throw AiUnavailableException(
            cleanErrors.joinToString(" ").ifBlank {
                "AI доставчиците временно не отговарят."
            },
        )
    }

    private fun routeGemini(apiKey: String, utterance: String): Decision {
        val models = linkedSetOf<String>()
        preferences.getString(KEY_ACTIVE_MODEL, null)?.let(models::add)
        models.addAll(PREFERRED_MODELS)

        var lastMessage = "Gemini временно не отговаря."
        for (model in models) {
            val result = requestGeminiDecision(
                apiKey = apiKey,
                model = model,
                utterance = utterance,
            )

            when {
                result.statusCode == 200 && result.body.isNotBlank() -> {
                    val decision = parseGeminiDecision(result.body)
                    rememberTurn(utterance, decision)
                    preferences.edit().putString(KEY_ACTIVE_MODEL, model).apply()
                    return decision
                }
                result.statusCode == 404 -> {
                    lastMessage = "Gemini моделът $model не е наличен."
                    continue
                }
                result.statusCode == 401 || result.statusCode == 403 -> {
                    throw AiUnavailableException(
                        "Gemini API ключът не е валиден или няма разрешение.",
                    )
                }
                result.statusCode == 429 -> {
                    throw AiUnavailableException(
                        "Лимитът на Gemini е достигнат. Преминавам към резервния AI.",
                    )
                }
                result.statusCode in 500..599 -> {
                    throw AiUnavailableException(
                        "Gemini временно не отговаря. Преминавам към резервния AI.",
                    )
                }
                else -> {
                    lastMessage = extractError(result.body, "Gemini заявката беше отхвърлена.")
                    break
                }
            }
        }

        throw AiUnavailableException(lastMessage)
    }

    private fun routeBackup(apiKey: String, utterance: String): Decision {
        val model = backupModel()
        val result = requestBackupDecision(
            apiKey = apiKey,
            model = model,
            utterance = utterance,
        )

        when {
            result.statusCode == 200 && result.body.isNotBlank() -> {
                val decision = parseBackupDecision(result.body)
                rememberTurn(utterance, decision)
                return decision
            }
            result.statusCode == 401 || result.statusCode == 403 -> {
                throw AiUnavailableException(
                    "Резервният API ключ не е валиден или няма разрешение.",
                )
            }
            result.statusCode == 404 -> {
                throw AiUnavailableException(
                    "Резервният модел $model не е наличен.",
                )
            }
            result.statusCode == 429 -> {
                throw AiUnavailableException(
                    "Лимитът на резервния AI доставчик също е достигнат.",
                )
            }
            result.statusCode in 500..599 -> {
                throw AiUnavailableException(
                    "Резервният AI доставчик временно не отговаря.",
                )
            }
            else -> {
                throw AiUnavailableException(
                    extractError(
                        result.body,
                        "Резервната AI заявка беше отхвърлена.",
                    ),
                )
            }
        }
    }

    private fun geminiApiKey(): String =
        preferences.getString(KEY_GEMINI_API_KEY, "").orEmpty().trim()

    private fun backupApiKey(): String =
        preferences.getString(KEY_BACKUP_API_KEY, "").orEmpty().trim()

    private fun backupBaseUrl(): String =
        preferences.getString(KEY_BACKUP_BASE_URL, DEFAULT_BACKUP_BASE_URL)
            .orEmpty()
            .trim()
            .ifBlank { DEFAULT_BACKUP_BASE_URL }
            .trimEnd('/')

    private fun backupModel(): String =
        preferences.getString(KEY_BACKUP_MODEL, DEFAULT_BACKUP_MODEL)
            .orEmpty()
            .trim()
            .ifBlank { DEFAULT_BACKUP_MODEL }

    private fun requestGeminiDecision(
        apiKey: String,
        model: String,
        utterance: String,
    ): HttpResult {
        val url = URL("$GEMINI_BASE_URL/models/$model:generateContent")
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
                        .put(
                            "role",
                            if (turn.role == "assistant") "model" else "user",
                        )
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
            val generationConfig = JSONObject().put("maxOutputTokens", 500)
            if (!model.startsWith("gemini-3.5") &&
                !model.startsWith("gemini-3.6")
            ) {
                generationConfig.put("temperature", 0.15)
            }
            put("generationConfig", generationConfig)
        }

        return executeRequest(connection, payload)
    }

    private fun requestBackupDecision(
        apiKey: String,
        model: String,
        utterance: String,
    ): HttpResult {
        val base = backupBaseUrl()
        val endpoint = if (base.endsWith("/chat/completions")) {
            base
        } else {
            "$base/chat/completions"
        }
        val connection = (URL(endpoint).openConnection() as HttpURLConnection).apply {
            requestMethod = "POST"
            connectTimeout = 15_000
            readTimeout = 45_000
            doOutput = true
            setRequestProperty("Content-Type", "application/json; charset=utf-8")
            setRequestProperty("Authorization", "Bearer $apiKey")
        }

        val messages = JSONArray().put(
            JSONObject()
                .put("role", "system")
                .put("content", SYSTEM_PROMPT),
        )
        conversation.forEach { turn ->
            messages.put(
                JSONObject()
                    .put("role", turn.role)
                    .put("content", turn.text),
            )
        }
        messages.put(
            JSONObject()
                .put("role", "user")
                .put("content", utterance),
        )

        val payload = JSONObject()
            .put("model", model)
            .put("messages", messages)

        val lowerModel = model.lowercase()
        val reasoningModel = lowerModel.startsWith("gpt-5") ||
            lowerModel.startsWith("o1") ||
            lowerModel.startsWith("o3") ||
            lowerModel.startsWith("o4")
        if (reasoningModel) {
            payload.put("max_completion_tokens", 500)
        } else {
            payload.put("max_tokens", 500)
            payload.put("temperature", 0.15)
        }

        return executeRequest(connection, payload)
    }

    private fun executeRequest(
        connection: HttpURLConnection,
        payload: JSONObject,
    ): HttpResult {
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

    private fun parseGeminiDecision(responseBody: String): Decision {
        val envelope = JSONObject(responseBody)
        val candidates = envelope.optJSONArray("candidates")
            ?: throw AiUnavailableException("Gemini върна празен отговор.")
        val candidate = candidates.optJSONObject(0)
            ?: throw AiUnavailableException("Gemini върна невалиден отговор.")
        val parts = candidate
            .optJSONObject("content")
            ?.optJSONArray("parts")
            ?: throw AiUnavailableException("Gemini отговорът няма съдържание.")

        val rawText = buildString {
            for (index in 0 until parts.length()) {
                val text = parts.optJSONObject(index)?.optString("text").orEmpty()
                if (text.isNotBlank()) append(text)
            }
        }.trim()

        return parseDecisionText(rawText)
    }

    private fun parseBackupDecision(responseBody: String): Decision {
        val envelope = JSONObject(responseBody)
        val choices = envelope.optJSONArray("choices")
            ?: throw AiUnavailableException("Резервният AI върна празен отговор.")
        val message = choices.optJSONObject(0)?.optJSONObject("message")
            ?: throw AiUnavailableException("Резервният AI върна невалиден отговор.")
        val rawText = message.optString("content", "").trim()
        return parseDecisionText(rawText)
    }

    private fun parseDecisionText(rawText: String): Decision {
        if (rawText.isBlank()) {
            throw AiUnavailableException("AI върна празен отговор.")
        }

        val cleanJson = rawText
            .removePrefix("```json")
            .removePrefix("```")
            .removeSuffix("```")
            .trim()
        val json = try {
            JSONObject(cleanJson)
        } catch (_: Exception) {
            throw AiUnavailableException("AI върна невалиден JSON отговор.")
        }
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
        val assistantContext = JSONObject()
            .put("action", decision.action)
            .put("argument", decision.argument)
            .put("reply", decision.reply)
            .toString()

        conversation.add(ConversationTurn("user", utterance.trim()))
        conversation.add(ConversationTurn("assistant", assistantContext))
        while (conversation.size > 12) {
            conversation.removeAt(0)
        }
    }

    private fun extractError(body: String, fallback: String): String {
        return try {
            val error = JSONObject(body).optJSONObject("error")
            error?.optString("message")
                ?.replace(Regex("\\s+"), " ")
                ?.trim()
                ?.take(240)
                .orEmpty()
                .ifBlank { fallback }
        } catch (_: Exception) {
            fallback
        }
    }
}
