import 'package:flutter/material.dart';

import '../services/local_store.dart';
import '../ui/common_widgets.dart';

class HomePage extends StatelessWidget {
  final LocalStore store;
  final ValueChanged<int> onOpenSection;

  const HomePage({
    super.key,
    required this.store,
    required this.onOpenSection,
  });

  Future<void> _openStudio() async {
    if (store.songProjects.isEmpty) {
      await store.startNewStudioProject();
    } else {
      await store.loadSongIntoStudio(store.songProjects.first);
    }
    onOpenSection(1);
  }

  @override
  Widget build(BuildContext context) {
    return IronBackground(
      child: AnimatedBuilder(
        animation: store,
        builder: (context, _) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 108),
            children: [
              Row(
                children: [
                  const Expanded(
                    child: PageTitle(
                      eyebrow: 'IRON 420',
                      title: 'Твоят AI асистент',
                      subtitle: 'Говори свободно. Iron помни контекста и действа.',
                    ),
                  ),
                  const SizedBox(width: 10),
                  NeonPill(
                    text: store.hasApiKey ? 'AI ONLINE' : 'НУЖЕН Е КЛЮЧ',
                    icon: store.hasApiKey
                        ? Icons.cloud_done_outlined
                        : Icons.key_outlined,
                    active: store.hasApiKey,
                  ),
                ],
              ),
              const SizedBox(height: 18),
              IronCard(
                bright: true,
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Container(
                      width: 92,
                      height: 92,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: ironGreen.withOpacity(0.10),
                        border: Border.all(
                          color: ironGreen.withOpacity(0.65),
                          width: 2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: ironGreen.withOpacity(0.22),
                            blurRadius: 28,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.graphic_eq_rounded,
                        color: ironGreen,
                        size: 48,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Кажи „Hey Iron“ или отвори AI разговора',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 19,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 7),
                    const Text(
                      'Не е нужно да помниш точни команди. Кажи нормално какво искаш.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white60,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 18),
                    IronButton(
                      text: 'ЗАПОЧНИ AI РАЗГОВОР',
                      icon: Icons.mic_rounded,
                      onPressed: () => onOpenSection(3),
                    ),
                  ],
                ),
              ),
              IronCard(
                child: Row(
                  children: [
                    Icon(
                      store.hasApiKey
                          ? Icons.verified_user_outlined
                          : Icons.warning_amber_rounded,
                      color:
                          store.hasApiKey ? ironGreen : Colors.orangeAccent,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        store.hasApiKey
                            ? 'Gemini ключът е готов. Гласовият AI режим може да разговаря и да изпълнява действия.'
                            : 'Отвори AI разговора и запази Gemini API ключ, за да работи свободният гласов режим.',
                        style: const TextStyle(
                          color: Colors.white70,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Инструменти',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _HomeAction(
                      icon: Icons.mic_external_on_outlined,
                      title: 'Rap Studio',
                      subtitle: 'Текстове и песни',
                      onTap: _openStudio,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _HomeAction(
                      icon: Icons.library_music_outlined,
                      title: 'Песни',
                      subtitle: '${store.songProjects.length} проекта',
                      onTap: () => onOpenSection(2),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _HomeAction(
                icon: Icons.tune_rounded,
                title: 'Телефон и Iron',
                subtitle: 'Събуждане, бързи действия и настройки',
                wide: true,
                onTap: () => onOpenSection(4),
              ),
              const SizedBox(height: 16),
              IronCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                child: const Row(
                  children: [
                    Icon(Icons.bolt_rounded, color: ironGreen),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Версия 3.4.0 • разговорен AI режим',
                        style: TextStyle(
                          color: ironGreenSoft,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _HomeAction extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool wide;

  const _HomeAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.wide = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          height: wide ? 88 : 116,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: ironPanelRaised.withOpacity(0.92),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: ironGreen.withOpacity(0.30)),
          ),
          child: wide
              ? Row(
                  children: [
                    _iconBox(),
                    const SizedBox(width: 14),
                    Expanded(child: _labels()),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: ironGreen,
                    ),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _iconBox(),
                    const Spacer(),
                    _labels(),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _iconBox() {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: ironGreen.withOpacity(0.10),
      ),
      child: Icon(icon, color: ironGreen, size: 22),
    );
  }

  Widget _labels() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: 15,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          subtitle,
          style: const TextStyle(
            color: Colors.white54,
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}
