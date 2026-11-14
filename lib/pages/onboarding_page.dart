import 'package:flutter/material.dart';

import '../services/local_store.dart';
import '../theme/iron_theme.dart';

class OnboardingPage extends StatefulWidget {
  final LocalStore store;

  const OnboardingPage({super.key, required this.store});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final PageController _controller = PageController();
  int _index = 0;

  static const _pages = <_OnboardSlide>[
    _OnboardSlide(
      icon: Icons.auto_awesome_rounded,
      title: 'Това е Iron',
      body:
          'Личен асистент на български за идеи, разговор и рап текстове. Тъмен екран, неоново зелено — без излишни решетки и радари.',
    ),
    _OnboardSlide(
      icon: Icons.mic_rounded,
      title: 'Говори или пиши',
      body:
          'Чатът е на първо място. Натисни микрофона и говори. Iron може и да чете отговорите на глас. Фоновото „Хей Айрън“ е временно изключено.',
    ),
    _OnboardSlide(
      icon: Icons.library_music_rounded,
      title: 'Студио и ключ',
      body:
          'Пиши текстове в Студио, запази песните локално и копирай пакет за Suno. За AI добави безплатен Gemini или Groq ключ — пази се криптирано на телефона.',
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _next() async {
    if (_index >= _pages.length - 1) {
      await widget.store.completeOnboarding();
      return;
    }
    await _controller.nextPage(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: ironDark,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            IronSpacing.page,
            IronSpacing.lg,
            IronSpacing.page,
            IronSpacing.lg,
          ),
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: widget.store.completeOnboarding,
                  child: const Text('Пропусни'),
                ),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _controller,
                  itemCount: _pages.length,
                  onPageChanged: (value) => setState(() => _index = value),
                  itemBuilder: (context, index) {
                    final page = _pages[index];
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 88,
                            height: 88,
                            decoration: BoxDecoration(
                              color: ironGreen.withValues(alpha: 0.12),
                              shape: BoxShape.circle,
                              border: Border.all(color: ironOutline, width: 1),
                            ),
                            child: Icon(page.icon, color: ironGreen, size: 40),
                          ),
                          const SizedBox(height: IronSpacing.lg),
                          Text(
                            page.title,
                            textAlign: TextAlign.center,
                            style: text.headlineMedium,
                          ),
                          const SizedBox(height: IronSpacing.md),
                          Text(
                            page.body,
                            textAlign: TextAlign.center,
                            style: text.bodyLarge?.copyWith(color: ironMuted),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_pages.length, (i) {
                  final selected = i == _index;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    height: 8,
                    width: selected ? 22 : 8,
                    decoration: BoxDecoration(
                      color: selected
                          ? ironGreen
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        width: 1,
                        color: selected ? ironGreen : ironOutlineMuted,
                      ),
                    ),
                  );
                }),
              ),
              const SizedBox(height: IronSpacing.lg),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _next,
                  child: Text(
                    _index == _pages.length - 1 ? 'Започни' : 'Напред',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OnboardSlide {
  final IconData icon;
  final String title;
  final String body;

  const _OnboardSlide({
    required this.icon,
    required this.title,
    required this.body,
  });
}
