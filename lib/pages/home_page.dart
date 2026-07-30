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
      duration: const Duration(milliseconds: 3000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IronBackground(
      child: AnimatedBuilder(
        animation: Listenable.merge([_controller, widget.store]),
        builder: (context, _) {
          return LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final compact = constraints.maxHeight < 760 || width < 390;
              final coreSize = (width * (compact ? 0.66 : 0.76))
                  .clamp(210.0, compact ? 238.0 : 292.0)
                  .toDouble();

              return SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: EdgeInsets.fromLTRB(
                  compact ? 14 : 18,
                  compact ? 4 : 10,
                  compact ? 14 : 18,
                  compact ? 8 : 18,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 620),
                    child: Column(
                      children: [
                        _TopHudBar(
                          online: widget.store.hasApiKey,
                          onMenu: () => widget.onOpenSection(4),
                          compact: compact,
                        ),
                        SizedBox(height: compact ? 2 : 7),
                        _ExactTitle(compact: compact),
                        SizedBox(height: compact ? 1 : 5),
                        CannabisCore(
                          progress: _controller.value,
                          size: coreSize,
                        ),
                        SizedBox(height: compact ? 1 : 4),
                        _ApiStatusCard(
                          hasApiKey: widget.store.hasApiKey,
                          compact: compact,
                        ),
                        SizedBox(height: compact ? 8 : 12),
                        GridView.count(
                          crossAxisCount: 2,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          mainAxisSpacing: compact ? 8 : 10,
                          crossAxisSpacing: compact ? 8 : 10,
                          childAspectRatio: compact ? 1.84 : 1.72,
                          children: [
                            _ExactActionCard(
                              icon: Icons.chat_bubble_outline_rounded,
                              title: 'ЧАТ',
                              subtitle: 'Говори с AI',
                              compact: compact,
                              onTap: () => widget.onOpenSection(3),
                            ),
                            _ExactActionCard(
                              icon: Icons.mic_none_rounded,
                              title: 'RAP STUDIO',
                              subtitle: 'Пиши и генерирай',
                              compact: compact,
                              onTap: () => widget.onOpenSection(1),
                            ),
                            _ExactActionCard(
                              icon: Icons.music_note_rounded,
                              title: 'ПЕСНИ',
                              subtitle: 'Моите проекти',
                              compact: compact,
                              onTap: () => widget.onOpenSection(2),
                            ),
                            _ExactActionCard(
                              icon: Icons.graphic_eq_rounded,
                              title: 'ГЛАС',
                              subtitle: 'BG микрофон',
                              compact: compact,
                              onTap: () => widget.onOpenSection(3),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _TopHudBar extends StatelessWidget {
  final bool online;
  final VoidCallback onMenu;
  final bool compact;

  const _TopHudBar({
    required this.online,
    required this.onMenu,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: compact ? 34 : 42,
      child: Row(
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onMenu,
              borderRadius: BorderRadius.circular(18),
              child: Padding(
                padding: EdgeInsets.all(compact ? 6 : 8),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: List.generate(
                    3,
                    (index) => Container(
                      width: index == 1
                          ? (compact ? 23 : 27)
                          : (compact ? 29 : 34),
                      height: 2,
                      margin: const EdgeInsets.symmetric(vertical: 2.5),
                      decoration: BoxDecoration(
                        color: ironGreenSoft,
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: const [
                          BoxShadow(color: ironGreen, blurRadius: 7),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const Spacer(),
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: online ? ironGreenSoft : Colors.orangeAccent,
              boxShadow: [
                BoxShadow(
                  color: (online ? ironGreen : Colors.orangeAccent)
                      .withOpacity(0.9),
                  blurRadius: 12,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }
}

class _ExactTitle extends StatelessWidget {
  final bool compact;

  const _ExactTitle({required this.compact});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (bounds) => const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.white,
              Color(0xFFE9F0EC),
              Color(0xFF9BA8A0),
              Colors.white,
            ],
            stops: [0, 0.38, 0.72, 1],
          ).createShader(bounds),
          child: Text(
            'IRON MUSIC',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: compact ? 31 : 38,
              height: 0.95,
              fontWeight: FontWeight.w900,
              letterSpacing: compact ? 1.3 : 1.7,
              shadows: const [
                Shadow(color: Colors.black, blurRadius: 5, offset: Offset(0, 2)),
              ],
            ),
          ),
        ),
        SizedBox(height: compact ? 1 : 3),
        Text(
          '420 AI',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: ironGreen,
            fontSize: compact ? 40 : 49,
            height: 0.94,
            fontWeight: FontWeight.w900,
            letterSpacing: compact ? 2.8 : 3.6,
            shadows: const [
              Shadow(color: ironGreen, blurRadius: 22),
              Shadow(color: ironGreen, blurRadius: 7),
            ],
          ),
        ),
        SizedBox(height: compact ? 5 : 8),
        Text(
          'ТВОЯТ AI РАП ПРОДУЦЕНТ',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: ironGreenSoft.withOpacity(0.88),
            fontSize: compact ? 9.5 : 11,
            fontWeight: FontWeight.w900,
            letterSpacing: compact ? 1.9 : 2.5,
            shadows: const [Shadow(color: ironGreen, blurRadius: 8)],
          ),
        ),
      ],
    );
  }
}

class _ApiStatusCard extends StatelessWidget {
  final bool hasApiKey;
  final bool compact;

  const _ApiStatusCard({
    required this.hasApiKey,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    final accent = hasApiKey ? ironGreen : Colors.orangeAccent;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 13 : 16,
        vertical: compact ? 8 : 11,
      ),
      decoration: BoxDecoration(
        color: const Color(0xE805100A),
        borderRadius: BorderRadius.circular(compact ? 16 : 18),
        border: Border.all(color: accent.withOpacity(0.46)),
        boxShadow: [
          BoxShadow(color: accent.withOpacity(0.11), blurRadius: 20),
          const BoxShadow(
            color: Colors.black54,
            blurRadius: 12,
            offset: Offset(0, 7),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: compact ? 36 : 42,
            height: compact ? 36 : 42,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: accent.withOpacity(0.08),
              border: Border.all(color: accent.withOpacity(0.5)),
            ),
            child: Icon(
              hasApiKey
                  ? Icons.verified_user_outlined
                  : Icons.key_off_outlined,
              color: accent,
              size: compact ? 21 : 25,
            ),
          ),
          SizedBox(width: compact ? 10 : 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    hasApiKey
                        ? 'API ключът е запазен'
                        : 'Gemini API ключ липсва',
                    maxLines: 1,
                    style: TextStyle(
                      color: accent,
                      fontSize: compact ? 14 : 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Gemini Flash • Български глас',
                    maxLines: 1,
                    style: TextStyle(
                      color: Colors.white60,
                      fontSize: compact ? 10.5 : 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: accent,
              boxShadow: [BoxShadow(color: accent, blurRadius: 10)],
            ),
          ),
        ],
      ),
    );
  }
}

class _ExactActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool compact;
  final VoidCallback onTap;

  const _ExactActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.compact,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final iconBox = compact ? 39.0 : 46.0;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xF00A2915),
                Color(0xF004160B),
                Color(0xF0010905),
              ],
            ),
            border: Border.all(color: ironGreen.withOpacity(0.72)),
            boxShadow: [
              BoxShadow(
                color: ironGreen.withOpacity(0.17),
                blurRadius: 18,
                spreadRadius: 0.2,
              ),
              const BoxShadow(
                color: Colors.black54,
                blurRadius: 10,
                offset: Offset(0, 7),
              ),
            ],
          ),
          child: Stack(
            children: [
              Positioned(
                left: 11,
                right: 11,
                top: 0,
                child: Container(
                  height: 1.3,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.transparent,
                        ironGreenSoft.withOpacity(0.95),
                        Colors.transparent,
                      ],
                    ),
                    boxShadow: const [
                      BoxShadow(color: ironGreen, blurRadius: 7),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: compact ? 9 : 12),
                child: Row(
                  children: [
                    Container(
                      width: iconBox,
                      height: iconBox,
                      decoration: BoxDecoration(
                        color: ironGreen.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(compact ? 12 : 14),
                        border: Border.all(color: ironGreen.withOpacity(0.28)),
                        boxShadow: [
                          BoxShadow(
                            color: ironGreen.withOpacity(0.1),
                            blurRadius: 12,
                          ),
                        ],
                      ),
                      child: Icon(
                        icon,
                        color: ironGreen,
                        size: compact ? 25 : 29,
                      ),
                    ),
                    SizedBox(width: compact ? 8 : 10),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: double.infinity,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                title,
                                maxLines: 1,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: compact ? 12.5 : 14,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.1,
                                ),
                              ),
                            ),
                          ),
                          SizedBox(height: compact ? 2 : 4),
                          SizedBox(
                            width: double.infinity,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                subtitle,
                                maxLines: 1,
                                style: TextStyle(
                                  color: Colors.white60,
                                  fontSize: compact ? 9.5 : 11,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
