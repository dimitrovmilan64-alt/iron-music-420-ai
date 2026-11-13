import 'package:flutter/material.dart';

import '../services/ai_provider_config.dart';
import '../services/hey_iron_controller.dart';
import '../services/iron_voice_flags.dart';
import '../services/local_store.dart';
import '../ui/common_widgets.dart';
import '../widgets/voice_settings_panel.dart';
import 'commands_page.dart';

class SettingsPage extends StatefulWidget {
  final LocalStore store;
  final HeyIronController? heyIron;
  final VoidCallback? onOpenChat;

  const SettingsPage({
    super.key,
    required this.store,
    this.heyIron,
    this.onOpenChat,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController _apiKeyController;
  late final TextEditingController _backupApiKeyController;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _apiKeyController = TextEditingController(text: widget.store.apiKey);
    _backupApiKeyController =
        TextEditingController(text: widget.store.backupApiKey);
    widget.store.addListener(_onStore);
  }

  @override
  void dispose() {
    widget.store.removeListener(_onStore);
    _apiKeyController.dispose();
    _backupApiKeyController.dispose();
    super.dispose();
  }

  void _onStore() {
    if (!mounted) return;
    setState(() {});
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _saveKeys() async {
    if (_saving) return;
    setState(() => _saving = true);
    final geminiKey = _apiKeyController.text.trim();
    final backupKey = _backupApiKeyController.text.trim();
    await widget.store.setApiKey(geminiKey);
    await widget.store.setBackupProvider(
      apiKey: backupKey,
      baseUrl: AiProviderConfig.defaultBackupBaseUrl,
      model: AiProviderConfig.defaultBackupModel,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (geminiKey.isEmpty && backupKey.isEmpty) {
      _toast('Добави Gemini или резервен AI API ключ.');
      return;
    }
    _toast('Gemini и Groq са запазени криптирано на телефона.');
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    return IronBackground(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 108),
        children: [
          const PageTitle(
            eyebrow: 'IRON',
            title: 'Настройки',
            subtitle: 'AI ключове, глас и бързи инструменти — на едно място.',
          ),
          const SizedBox(height: 18),
          IronCard(
            bright: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'AI доставчици',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Iron използва Gemini първо. При лимит или недостъпност автоматично преминава към Groq. Ключовете се пазят само локално на телефона.',
                  style: TextStyle(color: Colors.white60, height: 1.35),
                ),
                const SizedBox(height: 16),
                const Text(
                  '1. Основен доставчик · Gemini',
                  style: TextStyle(
                    color: ironGreen,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _apiKeyController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Gemini API ключ',
                    hintText: 'AIza...',
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  '2. Резервен доставчик · Groq',
                  style: TextStyle(
                    color: ironGreen,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Постави само Groq API ключа. Адресът и моделът се настройват автоматично.',
                  style: TextStyle(color: Colors.white60, height: 1.35),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _backupApiKeyController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Groq API ключ',
                    hintText: 'gsk_...',
                  ),
                ),
                const SizedBox(height: 16),
                IronButton(
                  text: _saving ? 'Запазване...' : 'Запази AI доставчиците',
                  icon: Icons.save_outlined,
                  onPressed: _saving ? null : _saveKeys,
                ),
              ],
            ),
          ),
          IronCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Гласови отговори',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  subtitle: const Text(
                    'Iron да чете отговорите на глас в чата.',
                    style: TextStyle(color: Colors.white60),
                  ),
                  value: store.voiceRepliesEnabled,
                  activeColor: ironGreen,
                  onChanged: (value) => store.setVoiceRepliesEnabled(value),
                ),
                const Divider(color: Colors.white12),
                if (widget.heyIron != null)
                  AnimatedBuilder(
                    animation: widget.heyIron!,
                    builder: (context, _) {
                      final hey = widget.heyIron!;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SwitchListTile.adaptive(
                            contentPadding: EdgeInsets.zero,
                            title: const Text(
                              'Хей Айрън',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            subtitle: Text(
                              '${hey.statusLabel}. При първо включване се изтегля офлайн модел от около ${HeyIronController.formatSize(HeyIronController.modelBytes)}. Слушането е само докато приложението е отворено.',
                              style: const TextStyle(color: Colors.white60, height: 1.35),
                            ),
                            value: hey.enabled,
                            activeColor: ironGreen,
                            onChanged: hey.phase == HeyIronPhase.downloading
                                ? null
                                : (value) => hey.setEnabled(value),
                          ),
                          if (hey.phase == HeyIronPhase.downloading)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: LinearProgressIndicator(
                                value: hey.downloadProgress == 0
                                    ? null
                                    : hey.downloadProgress,
                                color: ironGreen,
                                backgroundColor: ironLine,
                              ),
                            ),
                          Text(
                            hey.message,
                            style: const TextStyle(color: Colors.white70, height: 1.35),
                          ),
                          SwitchListTile.adaptive(
                            contentPadding: EdgeInsets.zero,
                            title: const Text(
                              'Слушай и на заден план',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            subtitle: const Text(
                              'Експериментално. Може да натовари слаби телефони. Изключено е по подразбиране.',
                              style: TextStyle(color: Colors.white60, height: 1.35),
                            ),
                            value: hey.backgroundExperimental,
                            activeColor: ironGreen,
                            onChanged: hey.enabled
                                ? (value) => hey.setBackgroundExperimental(value)
                                : null,
                          ),
                          if (hey.phase == HeyIronPhase.blocked)
                            TextButton(
                              onPressed: hey.resetWatchdog,
                              child: const Text('Нулирай защитата и пробвай пак'),
                            ),
                        ],
                      );
                    },
                  )
                else
                  Text(
                    ironVoiceServiceEnabled
                        ? 'Фоновото „Хей Айрън“ може да се включи от чата.'
                        : ironVoiceDisabledMessage,
                    style: const TextStyle(color: Colors.white70, height: 1.35),
                  ),
                if (widget.onOpenChat != null) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: widget.onOpenChat,
                      child: const Text('Отвори чата'),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          VoiceSettingsPanel(store: store),
          const SizedBox(height: 16),
          const Text(
            'Инструменти',
            style: TextStyle(
              color: Colors.white,
              fontSize: 19,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          CommandsToolsBody(store: store),
        ],
      ),
    );
  }
}
