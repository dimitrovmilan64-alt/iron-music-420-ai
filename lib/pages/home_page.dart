import 'package:flutter/material.dart';

import '../services/local_store.dart';
import '../ui/common_widgets.dart';

class HomePage extends StatefulWidget {
  final LocalStore store;
  final ValueChanged<int> onOpenSection;

  const HomePage({
    super.key,
    required this.store,
    required this.onOpenSection,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _continueLastProject() async {
    if (widget.store.songProjects.isEmpty) {
      await widget.store.startNewStudioProject();
    } else {
      await widget.store.loadSongIntoStudio(widget.store.songProjects.first);
    }
    widget.onOpenSection(1);
  }

  @override
  Widget build(BuildContext context) {
    return IronBackground(
      child: AnimatedBuilder(
        animation: Listenable.merge([_controller, widget.store]),
        builder: (context, _) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 112),
            children: [
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: ironPanelRaised.withOpacity(0.9),
                      border: Border.all(
                        color: ironGreen.withOpacity(0.28),
                      ),
                    ),
                    child: const Icon(
                      Icons.graphic_eq,
                      color: ironGreen,
                      size: 21,
                    ),
                  ),
                  const Spacer(),
                  NeonPill(
                    text: widget.store.hasApiKey ? 'AI ONLINE' : 'API KEY',
                    icon: widget.store.hasApiKey
                        ? Icons.cloud_done_outlined
                        : Icons.key_outlined,
                    active: widget.store.hasApiKey,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ShaderMask(
                blendMode: BlendMode.srcIn,
                shaderCallback: (bounds) => const LinearGradient(
                  colors: [Colors.white, Color(0xFFD5FFE2), ironGreenSoft],
                  stops: [0.0, 0.52, 1.0],
                ).createShader(bounds),
                child: const Text(
                  'IRON MUSIC',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2.2,
                    height: 1,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              const Text(
                '420 AI',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: ironGreen,
                  fontSize: 38,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 3,
                  height: 1.05,
                  shadows: [
                    Shadow(color: ironGreen, blurRadius: 18),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'ТВОЯТ AI РАП ПРОДУЦЕНТ',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: ironGreen.withOpacity(0.78),
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2.3,
                ),
              ),
              const SizedBox(height: 6),
              Center(
                child: CannabisCore(
                  progress: _controller.value,
                  size: 224,
                ),
              ),
              const SizedBox(height: 4),
              IronCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                margin: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: ironGreen.withOpacity(0.1),
                        border: Border.all(
                          color: ironGreen.withOpacity(0.35),
                        ),
                      ),
                      child: Icon(
                        widget.store.hasApiKey
                            ? Icons.verified_user_outlined
                            : Icons.key_off_outlined,
                        color: widget.store.hasApiKey
                            ? ironGreen
                            : Colors.orangeAccent,
                      ),
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.store.hasApiKey
                                ? 'API ключът е запазен'
                                : 'Gemini API ключ липсва',
                            style: const TextStyle(
                              color: ironGreenSoft,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 2),
                          const Text(
                            'Gemini Flash • Български глас • Локално',
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: widget.store.hasApiKey
                            ? ironGreen
                            : Colors.orangeAccent,
                        boxShadow: [
                          BoxShadow(
                            color: (widget.store.hasApiKey
                                    ? ironGreen
                                    : Colors.orangeAccent)
                                .withOpacity(0.8),
                            blurRadius: 9,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: _MetricBox(
                      icon: Icons.library_music_outlined,
                      value: '${widget.store.songProjects.length}',
                      label: 'Песни',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _MetricBox(
                      icon: Icons.forum_outlined,
                      value: '${widget.store.chatHistory.length}',
                      label: 'Съобщения',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  const Text(
                    'Бърз старт',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 20,
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Container(
                      height: 1,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            ironGreen.withOpacity(0.48),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 11),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1.17,
                children: [
                  _QuickAction(
                    icon: Icons.chat_bubble_outline,
                    title: 'ЧАТ',
                    subtitle: 'Говори с AI',
                    onTap: () => widget.onOpenSection(3),
                  ),
                  _QuickAction(
                    icon: Icons.mic_external_on_outlined,
                    title: 'RAP STUDIO',
                    subtitle: 'Пиши и генерирай',
                    onTap: () => widget.onOpenSection(1),
                  ),
                  _QuickAction(
                    icon: Icons.library_music_outlined,
                    title: 'ПЕСНИ',
                    subtitle: 'Моите проекти',
                    onTap: () => widget.onOpenSection(2),
                  ),
                  _QuickAction(
                    icon: Icons.graphic_eq,
                    title: 'IRON',
                    subtitle: 'Хей, Iron',
                    onTap: () => widget.onOpenSection(4),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              IronButton(
                text: widget.store.songProjects.isEmpty
                    ? 'ЗАПОЧНИ НОВ ПРОЕКТ'
                    : 'ПРОДЪЛЖИ ПОСЛЕДНИЯ ПРОЕКТ',
                icon: widget.store.songProjects.isEmpty
                    ? Icons.add
                    : Icons.play_arrow_rounded,
                onPressed: _continueLastProject,
              ),
              const SizedBox(height: 14),
              IronCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text(
                          'Версия 2.6.2',
                          style: TextStyle(
                            color: ironGreen,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const Spacer(),
                        NeonPill(
                          text: '420 CORE',
                          icon: Icons.bolt,
                          active: true,
                        ),
                      ],
                    ),
                    const SizedBox(height: 9),
                    const StatusLine(
                      icon: Icons.auto_awesome,
                      text: 'Нов неонов HUD интерфейс и AI ядро',
                    ),
                    const StatusLine(
                      icon: Icons.music_note,
                      text: 'Lyrics, Style of Music и Exclude за Suno',
                    ),
                    const StatusLine(
                      icon: Icons.save_outlined,
                      text: 'Автозапазване, библиотека и TXT експорт',
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

class _MetricBox extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;

  const _MetricBox({
    required this.icon,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            ironPanelRaised.withOpacity(0.94),
            ironPanel.withOpacity(0.96),
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: ironGreen.withOpacity(0.28)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: ironGreen.withOpacity(0.09),
            ),
            child: Icon(icon, color: ironGreen, size: 20),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    color: ironGreen,
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _QuickAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFF0A2814).withOpacity(0.92),
                ironPanel.withOpacity(0.98),
                const Color(0xFF010904),
              ],
            ),
            border: Border.all(color: ironGreen.withOpacity(0.42)),
            boxShadow: [
              BoxShadow(
                color: ironGreen.withOpacity(0.08),
                blurRadius: 17,
              ),
            ],
          ),
          child: Stack(
            children: [
              Positioned(
                right: -9,
                bottom: -12,
                child: Icon(
                  icon,
                  size: 72,
                  color: ironGreen.withOpacity(0.035),
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 39,
                    height: 39,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: ironGreen.withOpacity(0.1),
                      border: Border.all(
                        color: ironGreen.withOpacity(0.32),
                      ),
                    ),
                    child: Icon(icon, color: ironGreen, size: 23),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 11,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
