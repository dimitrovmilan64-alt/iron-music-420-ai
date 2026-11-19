import 'package:flutter/material.dart';

import '../services/iron_tts.dart';
import '../services/local_store.dart';
import '../ui/common_widgets.dart';

class VoiceSettingsPanel extends StatefulWidget {
  const VoiceSettingsPanel({super.key, required this.store});

  final LocalStore store;

  @override
  State<VoiceSettingsPanel> createState() => _VoiceSettingsPanelState();
}

class _VoiceSettingsPanelState extends State<VoiceSettingsPanel> {
  final IronTts _tts = IronTts.instance;
  List<IronVoiceOption> _voices = const [];
  IronVoiceOption? _selected;
  bool _loading = true;
  bool _previewing = false;
  String? _status;
  late double _rate;
  late double _pitch;

  @override
  void initState() {
    super.initState();
    _rate = widget.store.ttsRate;
    _pitch = widget.store.ttsPitch;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _status = null;
    });
    final immediate = IronTts.cloudVoices(
      hasGemini: widget.store.hasApiKey,
      hasGroq: widget.store.hasBackupProvider,
    );
    final selected = await _tts.resolveSelection(widget.store, immediate);
    if (!mounted) return;
    setState(() {
      _voices = immediate;
      _selected = selected;
      _loading = immediate.isEmpty;
    });

    final voices = await _tts.listVoices(widget.store);
    if (!mounted) return;
    final resolved = await _tts.resolveSelection(widget.store, voices);
    if (!mounted) return;
    setState(() {
      _voices = voices;
      _selected = resolved;
      _loading = false;
    });
  }

  Future<void> _select(IronVoiceOption voice) async {
    await widget.store.saveVoiceSettings(
      rate: widget.store.ttsRate,
      pitch: widget.store.ttsPitch,
      voiceName:
          voice.provider == IronTtsProvider.device ? voice.name : voice.id,
      voiceLocale: voice.locale,
    );
    if (!mounted) return;
    setState(() => _selected = voice);
  }

  Future<void> _saveSliders(
      {required double rate, required double pitch}) async {
    final selected = _selected;
    await widget.store.saveVoiceSettings(
      rate: rate,
      pitch: pitch,
      voiceName: selected == null
          ? widget.store.ttsVoiceName
          : (selected.provider == IronTtsProvider.device
              ? selected.name
              : selected.id),
      voiceLocale: selected?.locale ?? widget.store.ttsVoiceLocale,
    );
    if (mounted) setState(() {});
  }

  Future<void> _preview(IronVoiceOption voice) async {
    setState(() {
      _previewing = true;
      _status = 'Пускам проба…';
    });
    final sample = voice.supportsBulgarian
        ? 'Здравей, аз съм Айрън. Ето как звучи този глас.'
        : 'Hello, I am Iron. This voice is English only.';
    final notice = await _tts.speakWith(sample, widget.store, voice);
    if (!mounted) return;
    setState(() {
      _previewing = false;
      _status = notice ?? 'Готово.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final geminiReady = store.hasApiKey;
    final groqReady = store.hasBackupProvider;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Глас',
          style: TextStyle(
            color: Colors.white,
            fontSize: 19,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          geminiReady
              ? 'Gemini гласовете работят и на български. Groq е само за английски.'
              : 'Избери глас от телефона. Ако добавиш Gemini ключ по-горе, ще се появят по-естествени облачни гласове, включително на български.',
          style: const TextStyle(color: Colors.white70, height: 1.35),
        ),
        const SizedBox(height: 10),
        IronCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _slider(
                label: 'Скорост',
                value: _rate,
                min: 0.3,
                max: 0.7,
                onChanged: (value) => setState(() => _rate = value),
                onChangeEnd: (value) =>
                    _saveSliders(rate: value, pitch: _pitch),
              ),
              const SizedBox(height: 8),
              _slider(
                label: 'Височина',
                value: _pitch,
                min: 0.8,
                max: 1.3,
                onChanged: (value) => setState(() => _pitch = value),
                onChangeEnd: (value) => _saveSliders(rate: _rate, pitch: value),
              ),
              if (_status != null) ...[
                const SizedBox(height: 8),
                Text(_status!,
                    style:
                        const TextStyle(color: Colors.white70, height: 1.35)),
              ],
              if (!geminiReady || !groqReady) ...[
                const SizedBox(height: 8),
                Text(
                  [
                    if (!geminiReady)
                      'Добави Gemini ключ за облачни гласове на български.',
                    if (!groqReady)
                      'Добави Groq ключ за облачни английски гласове.',
                  ].join(' '),
                  style: const TextStyle(
                      color: Colors.white54, height: 1.35, fontSize: 13),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 10),
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text(
              'Зареждане на гласовете…',
              style: TextStyle(color: Colors.white60),
            ),
          )
        else
          IronCard(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _voices.length,
                separatorBuilder: (_, __) =>
                    const Divider(height: 1, color: ironOutlineMuted),
                itemBuilder: (context, index) {
                  final voice = _voices[index];
                  final selected = _selected?.id == voice.id;
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    selected: selected,
                    title: Text(
                      voice.title,
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight:
                            selected ? FontWeight.w800 : FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      '${voice.locale} · ${voice.badge}',
                      style:
                          const TextStyle(color: Colors.white60, fontSize: 12),
                    ),
                    trailing: IconButton(
                      tooltip: 'Прослушай',
                      onPressed: _previewing ? null : () => _preview(voice),
                      icon: Icon(
                        Icons.play_circle_outline,
                        color: _previewing ? Colors.white38 : ironGreen,
                      ),
                    ),
                    onTap: () => _select(voice),
                  );
                },
              ),
            ),
          ),
      ],
    );
  }

  Widget _slider({
    required String label,
    required double value,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
    required ValueChanged<double> onChangeEnd,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label,
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w700)),
            const Spacer(),
            Text(value.toStringAsFixed(2),
                style: const TextStyle(color: Colors.white60)),
          ],
        ),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          onChanged: onChanged,
          onChangeEnd: onChangeEnd,
        ),
      ],
    );
  }
}
