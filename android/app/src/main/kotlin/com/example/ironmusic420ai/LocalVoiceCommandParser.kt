package com.example.ironmusic420ai

import java.util.Locale

data class LocalVoiceCommand(
    val action: String,
    val argument: String = "",
    val reply: String = "",
    val studioOutputType: String = "",
)

/**
 * Deterministic command layer used before cloud AI.
 * Phone and app actions remain available even when Gemini and Groq are limited.
 */
object LocalVoiceCommandParser {
    private val youtubeSearchPatterns = listOf(
        Regex(
            """^(?:отвори\s+)?(?:youtube|ютуб)\s+(?:и\s+)?(?:пусни(?:\s+ми)?|намери|потърси|търси|покажи|play|find|search(?:\s+for)?)\s+(.+)$""",
        ),
        Regex(
            """^(?:пусни(?:\s+ми)?|намери|потърси|търси|покажи|play|find|search(?:\s+for)?)\s+(?:в\s+|на\s+|in\s+|on\s+)?(?:youtube|ютуб)\s+(.+)$""",
        ),
        Regex(
            """^(?:пусни(?:\s+ми)?|намери|потърси|търси|покажи|play|find|search(?:\s+for)?)\s+(.+?)\s+(?:в|на|in|on)\s+(?:youtube|ютуб)$""",
        ),
        Regex("""^(?:youtube|ютуб)\s+(.+)$"""),
        Regex(
            """^(?:пусни(?:\s+ми)?|намери|потърси|търси|покажи|play|find|search(?:\s+for)?)\s+(?:песента|песен|клипа|клип|видеото|видео|song|video)\s+(.+)$""",
        ),
    )

    fun parse(rawValue: String): LocalVoiceCommand? {
        val command = normalize(rawValue)
        if (command.isBlank()) return null
        val youtubeQuery = extractYouTubeQuery(command)

        fun hasAny(vararg values: String): Boolean =
            values.any { command.contains(it) }

        fun startsWithAny(vararg values: String): Boolean =
            values.any { command.startsWith(it) }

        when {
            startsWithAny("automate ", "аутомейт ", "макро ", "макродроид ") -> {
                val argument = command
                    .replaceFirst(Regex("^(automate|аутомейт|макро(дроид)?)\\s+"), "")
                    .trim()
                return LocalVoiceCommand(
                    action = "automate",
                    argument = argument,
                    reply = if (argument.isBlank()) {
                        "Кажи името на Automate командата."
                    } else {
                        "Изпращам командата."
                    },
                )
            }

            youtubeQuery != null ->
                return LocalVoiceCommand(
                    action = "youtube_search",
                    argument = youtubeQuery,
                    reply = "Търся в YouTube.",
                )

            hasAny("фенер", "flashlight", "flash") &&
                hasAny("изключи", "спри", "изгаси", "угаси", "не включвай", "flash off", "turn off") ->
                return LocalVoiceCommand("flash_off", reply = "Фенерчето е изключено.")

            hasAny("фенер", "flashlight", "flash") &&
                hasAny("включи", "пусни", "светни", "flash on", "turn on") ->
                return LocalVoiceCommand("flash_on", reply = "Фенерчето е включено.")

            command in setOf("фенер", "фенерче", "фенерчето", "flashlight") ->
                return LocalVoiceCommand("flash_on", reply = "Фенерчето е включено.")

            hasAny("музикален режим", "music mode", "пусни музика", "режим музика") ->
                return LocalVoiceCommand("music_mode", reply = "Музикалният режим е включен.")

            hasAny("намали звука", "по тихо", "по-тихо", "volume down", "turn it down") ->
                return LocalVoiceCommand("volume_down", reply = "Звукът е намален.")

            hasAny("увеличи звука", "по силно", "по-силно", "volume up", "turn it up") ->
                return LocalVoiceCommand("volume_up", reply = "Звукът е увеличен.")

            hasAny("нощен режим", "night mode") ->
                return LocalVoiceCommand("night_mode", reply = "Нощният режим е включен.")

            hasAny(
                "направи рап текст",
                "напиши рап текст",
                "създай рап текст",
                "направи песен",
                "напиши песен",
                "write a rap",
                "make a rap",
                "write rap lyrics",
            ) ->
                return LocalVoiceCommand(
                    action = "studio_generate",
                    argument = rawValue.trim(),
                    reply = "Отварям Рап студио и започвам текста.",
                    studioOutputType = "Цяла песен",
                )

            hasAny(
                "дай рими",
                "направи рими",
                "измисли рими",
                "punchlines",
                "дай punchline",
                "give me rhymes",
                "write rhymes",
            ) ->
                return LocalVoiceCommand(
                    action = "studio_generate",
                    argument = rawValue.trim(),
                    reply = "Отварям Рап студио и подготвям рими.",
                    studioOutputType = "Рими и punchlines",
                )

            hasAny(
                "направи припев",
                "напиши припев",
                "дай припев",
                "направи рефрен",
                "припев",
                "рефрен",
                "write a chorus",
                "make a hook",
                "chorus",
            ) ->
                return LocalVoiceCommand(
                    action = "studio_generate",
                    argument = rawValue.trim(),
                    reply = "Отварям Рап студио и правя припев.",
                    studioOutputType = "Припев",
                )

            hasAny("отвори рап студио", "отвори студиото", "рап студио", "rap studio", "open studio") ->
                return LocalVoiceCommand("studio", reply = "Отварям Рап студио.")

            hasAny("отвори чата", "покажи чата", "ai чат", "open chat", "chat mode") ->
                return LocalVoiceCommand("chat", reply = "Отварям AI чата.")

            hasAny("отвори песните", "моите песни", "библиотека", "open songs", "song library") ->
                return LocalVoiceCommand("songs", reply = "Отварям песните.")

            hasAny("начален екран", "отвори начало", "към начало", "home screen", "go home") ->
                return LocalVoiceCommand("home", reply = "Отварям началния екран.")

            command in setOf(
                "youtube",
                "ютуб",
                "отвори youtube",
                "отвори ютуб",
                "пусни youtube",
                "пусни ютуб",
                "open youtube",
            ) ->
                return LocalVoiceCommand("youtube", reply = "Отварям YouTube.")

            hasAny("отвори камерата", "пусни камерата", "камера", "open camera") ->
                return LocalVoiceCommand("camera", reply = "Отварям камерата.")

            hasAny("отвори картите", "пусни картите", "карти", "open maps") ->
                return LocalVoiceCommand("maps", reply = "Отварям картите.")

            hasAny("отвори алармите", "покажи алармите", "аларми", "open alarms") ->
                return LocalVoiceCommand("alarms", reply = "Отварям алармите.")

            hasAny("отвори календара", "покажи календара", "календар", "open calendar") ->
                return LocalVoiceCommand("calendar", reply = "Отварям календара.")

            hasAny("отвори телефона", "отвори набиране", "набиране", "open dialer", "open phone") ->
                return LocalVoiceCommand("dialer", reply = "Отварям телефона.")

            hasAny("отвори bluetooth", "блутут", "bluetooth settings") ->
                return LocalVoiceCommand("bluetooth", reply = "Отварям Bluetooth.")

            hasAny("отвори wi fi", "отвори wifi", "уай фай", "wifi settings", "wi fi settings") ->
                return LocalVoiceCommand("wifi", reply = "Отварям Wi-Fi.")

            hasAny("отвори настройките", "системни настройки", "open settings") ->
                return LocalVoiceCommand("settings", reply = "Отварям настройките.")

            hasAny("отвори chrome", "отвори браузъра", "браузър", "open chrome", "open browser") ->
                return LocalVoiceCommand("chrome", reply = "Отварям браузъра.")

            command in setOf("отвори", "пусни", "направи", "open", "start", "create") ->
                return LocalVoiceCommand(
                    action = "clarify",
                    reply = "Кажи какво точно да отворя или направя.",
                )
        }

        return null
    }

    private fun extractYouTubeQuery(command: String): String? {
        for (pattern in youtubeSearchPatterns) {
            val match = pattern.matchEntire(command) ?: continue
            val query = match.groupValues[1]
                .replaceFirst(
                    Regex("""^(?:песента|песен|клипа|клип|видеото|видео|song|video)\s+"""),
                    "",
                )
                .trim()
            if (query.isNotBlank()) return query
        }
        return null
    }

    private fun normalize(value: String): String {
        return value
            .lowercase(Locale("bg", "BG"))
            .replace(Regex("[^a-zа-я0-9+\\- ]", RegexOption.IGNORE_CASE), " ")
            .replace(Regex("\\s+"), " ")
            .trim()
    }
}
