import 'dart:math' as math;

import 'package:flutter/material.dart';

const ironGreen = Color(0xFF00FF66);
const ironGreenSoft = Color(0xFF37FF88);
const ironGreenDeep = Color(0xFF008F43);
const ironDark = Color(0xFF010603);
const ironPanel = Color(0xFF031108);
const ironPanelRaised = Color(0xFF061A0D);
const ironLine = Color(0xFF0A3A1C);

String cleanMarkdownForDisplay(String text) {
  try {
    var result = text.replaceAll('\r\n', '\n');
    result = result.replaceAll(RegExp(r'```[a-zA-Z0-9_-]*'), '');
    result = result.replaceAll('```', '');
    result = result.replaceAll(
      RegExp(r'^\s{0,3}#{1,6}\s*', multiLine: true),
      '',
    );
    result = result.replaceAll('**', '');
    result = result.replaceAll('__', '');
    result = result.replaceAll('`', '');
    result = result.replaceAll(
      RegExp(r'^\s*[-*]\s+', multiLine: true),
      '• ',
    );
    result = result.replaceAll('*', '');
    result = result.replaceAll(
      RegExp(r'^\s*>\s?', multiLine: true),
      '',
    );
    result = result.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    return result.trim();
  } catch (_) {
    return text
        .replaceAll('**', '')
        .replaceAll('*', '')
        .replaceAll('`', '')
        .trim();
  }
}

String cleanTextForSpeech(String text) {
  try {
    var result = cleanMarkdownForDisplay(text);
    result = result.replaceAll(RegExp(r'[\[\]{}]'), ' ');
    result = result.replaceAll(
      RegExp(r'^\s*•\s*', multiLine: true),
      '',
    );
    result = result.replaceAll(RegExp(r'\n+'), '. ');
    result = result.replaceAll(RegExp(r'\s+'), ' ');
    result = result.replaceAll(RegExp(r'\.{2,}'), '.');
    return result.trim();
  } catch (_) {
    return text.replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}

class IronBackground extends StatelessWidget {
  final Widget child;
  final bool showHud;

  const IronBackground({
    super.key,
    required this.child,
    this.showHud = true,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0.0, -0.78),
          radius: 1.35,
          colors: [
            Color(0xFF063319),
            Color(0xFF011008),
            ironDark,
            Colors.black,
          ],
          stops: [0.0, 0.35, 0.72, 1.0],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (showHud)
            const IgnorePointer(
              child: CustomPaint(painter: _HudBackgroundPainter()),
            ),
          SafeArea(child: child),
        ],
      ),
    );
  }
}

class PageTitle extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget? trailing;
  final String? eyebrow;

  const PageTitle({
    super.key,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.eyebrow,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (eyebrow != null) ...[
                Text(
                  eyebrow!.toUpperCase(),
                  style: TextStyle(
                    color: ironGreen.withOpacity(0.72),
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2.0,
                  ),
                ),
                const SizedBox(height: 5),
              ],
              ShaderMask(
                blendMode: BlendMode.srcIn,
                shaderCallback: (bounds) => const LinearGradient(
                  colors: [ironGreenSoft, ironGreen],
                ).createShader(bounds),
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 27,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.2,
                    height: 1.05,
                  ),
                ),
              ),
              const SizedBox(height: 7),
              Text(
                subtitle,
                style: const TextStyle(
                  color: Colors.white60,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 10),
              Container(
                width: 86,
                height: 2,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      ironGreen,
                      ironGreen.withOpacity(0.05),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(9),
                ),
              ),
            ],
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 12),
          trailing!,
        ],
      ],
    );
  }
}

class IronCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final bool bright;
  final BorderRadius? borderRadius;

  const IronCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin = const EdgeInsets.only(bottom: 12),
    this.bright = false,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? BorderRadius.circular(20);
    return Container(
      width: double.infinity,
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: ironGreen.withOpacity(bright ? 0.16 : 0.07),
            blurRadius: bright ? 28 : 18,
            spreadRadius: bright ? 1 : 0,
          ),
          const BoxShadow(
            color: Colors.black54,
            blurRadius: 16,
            offset: Offset(0, 9),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: CustomPaint(
          foregroundPainter: _PanelAccentPainter(
            color: bright ? ironGreenSoft : ironGreen,
          ),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              borderRadius: radius,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  bright
                      ? const Color(0xFF0A2814).withOpacity(0.98)
                      : ironPanelRaised.withOpacity(0.96),
                  ironPanel.withOpacity(0.97),
                  const Color(0xFF010A05).withOpacity(0.98),
                ],
              ),
              border: Border.all(
                color: ironGreen.withOpacity(bright ? 0.62 : 0.34),
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

class IronInput extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final int maxLines;
  final int minLines;
  final bool obscureText;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onChanged;
  final IconData? icon;

  const IronInput({
    super.key,
    required this.controller,
    required this.label,
    required this.hint,
    this.maxLines = 1,
    this.minLines = 1,
    this.obscureText = false,
    this.textInputAction,
    this.onChanged,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      minLines: obscureText ? 1 : minLines,
      maxLines: obscureText ? 1 : maxLines,
      obscureText: obscureText,
      textInputAction: textInputAction,
      onChanged: onChanged,
      style: const TextStyle(color: Colors.white, height: 1.35),
      cursorColor: ironGreen,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: icon == null ? null : Icon(icon, color: ironGreen),
        labelStyle: const TextStyle(
          color: ironGreen,
          fontWeight: FontWeight.w600,
        ),
        floatingLabelStyle: const TextStyle(
          color: ironGreenSoft,
          fontWeight: FontWeight.w700,
        ),
        hintStyle: const TextStyle(color: Colors.white30),
        filled: true,
        fillColor: const Color(0xFF010A05).withOpacity(0.92),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(17),
          borderSide: BorderSide(color: ironGreen.withOpacity(0.29)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(17),
          borderSide: const BorderSide(color: ironGreen, width: 1.6),
        ),
      ),
    );
  }
}

class IronButton extends StatelessWidget {
  final String text;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool secondary;
  final bool compact;

  const IronButton({
    super.key,
    required this.text,
    required this.icon,
    required this.onPressed,
    this.secondary = false,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final radius = BorderRadius.circular(compact ? 15 : 18);
    return SizedBox(
      height: compact ? 46 : 54,
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        child: InkWell(
          onTap: onPressed,
          borderRadius: radius,
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: radius,
              gradient: secondary
                  ? LinearGradient(
                      colors: [
                        ironPanelRaised.withOpacity(enabled ? 0.96 : 0.55),
                        ironPanel.withOpacity(enabled ? 0.98 : 0.55),
                      ],
                    )
                  : LinearGradient(
                      colors: enabled
                          ? const [ironGreenSoft, ironGreen]
                          : [
                              ironGreen.withOpacity(0.28),
                              ironGreenDeep.withOpacity(0.2),
                            ],
                    ),
              border: secondary
                  ? Border.all(
                      color: ironGreen.withOpacity(enabled ? 0.62 : 0.2),
                    )
                  : null,
              boxShadow: enabled
                  ? [
                      BoxShadow(
                        color: ironGreen.withOpacity(secondary ? 0.08 : 0.24),
                        blurRadius: 16,
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: compact ? 18 : 20,
                  color: secondary ? ironGreen : Colors.black,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    text,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: secondary ? ironGreen : Colors.black,
                      fontWeight: FontWeight.w900,
                      fontSize: compact ? 12 : 14,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class StatusLine extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;

  const StatusLine({
    super.key,
    required this.icon,
    required this.text,
    this.color = ironGreen,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withOpacity(0.09),
              border: Border.all(color: color.withOpacity(0.28)),
            ),
            child: Icon(icon, size: 15, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: Colors.white70, height: 1.25),
            ),
          ),
        ],
      ),
    );
  }
}

class NeonPill extends StatelessWidget {
  final String text;
  final IconData? icon;
  final bool active;

  const NeonPill({
    super.key,
    required this.text,
    this.icon,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: active
            ? ironGreen.withOpacity(0.15)
            : Colors.black.withOpacity(0.28),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: ironGreen.withOpacity(active ? 0.7 : 0.28),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, color: ironGreen, size: 14),
            const SizedBox(width: 5),
          ],
          Text(
            text,
            style: TextStyle(
              color: active ? ironGreenSoft : Colors.white70,
              fontWeight: active ? FontWeight.w800 : FontWeight.w500,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

enum IronCoreState {
  idle,
  listening,
  thinking,
  speaking,
}

Color _ironCoreStateColor(IronCoreState state) {
  return switch (state) {
    IronCoreState.idle => ironGreen,
    IronCoreState.listening => const Color(0xFF70FFB0),
    IronCoreState.thinking => const Color(0xFF00E5A0),
    IronCoreState.speaking => const Color(0xFFA8FF70),
  };
}

double _ironCoreEnergy(IronCoreState state) {
  return switch (state) {
    IronCoreState.idle => 0.32,
    IronCoreState.listening => 0.88,
    IronCoreState.thinking => 1.0,
    IronCoreState.speaking => 0.78,
  };
}

class CannabisCore extends StatelessWidget {
  final double progress;
  final double size;
  final IronCoreState state;

  const CannabisCore({
    super.key,
    required this.progress,
    this.size = 300,
    this.state = IronCoreState.idle,
  });

  @override
  Widget build(BuildContext context) {
    final energy = _ironCoreEnergy(state);
    final cycle = progress * math.pi * 2;
    final breath = 0.965 +
        ((math.sin(cycle) + 1) * 0.5) * (0.012 + energy * 0.018);
    return RepaintBoundary(
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _IronCoreSpherePainter(
                  progress: progress,
                  state: state,
                ),
              ),
            ),
            Transform.scale(
              scale: breath,
              child: ClipOval(
                child: Opacity(
                  opacity: 0.54 + energy * 0.12,
                  child: Transform.rotate(
                    angle: math.sin(cycle * 0.40) * 0.012,
                    child: Image.asset(
                      'assets/images/hud_core_exact.png',
                      width: size * 0.93,
                      height: size * 0.93,
                      fit: BoxFit.cover,
                      filterQuality: FilterQuality.high,
                      errorBuilder: (context, error, stackTrace) => CustomPaint(
                        size: Size.square(size * 0.93),
                        painter: _HudCorePainter(progress: progress),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _IronCoreGlassPainter(
                    progress: progress,
                    state: state,
                  ),
                ),
              ),
            ),
            Positioned(
              left: size * 0.12,
              right: size * 0.12,
              bottom: size * 0.045,
              height: size * 0.20,
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _IronCorePedestalPainter(
                    progress: progress,
                    state: state,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class IronBottomNavigation extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final List<IronNavItem> items;

  const IronBottomNavigation({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF010A05).withOpacity(0.98),
        border: Border(
          top: BorderSide(color: ironGreen.withOpacity(0.18)),
        ),
        boxShadow: [
          BoxShadow(
            color: ironGreen.withOpacity(0.08),
            blurRadius: 22,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 70,
          child: Row(
            children: List.generate(items.length, (index) {
              final item = items[index];
              final selected = index == selectedIndex;
              return Expanded(
                child: InkWell(
                  onTap: () => onSelected(index),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOut,
                        width: selected ? 50 : 38,
                        height: 32,
                        decoration: BoxDecoration(
                          color: selected
                              ? ironGreen.withOpacity(0.14)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(18),
                          border: selected
                              ? Border.all(
                                  color: ironGreen.withOpacity(0.22),
                                )
                              : null,
                          boxShadow: selected
                              ? [
                                  BoxShadow(
                                    color: ironGreen.withOpacity(0.12),
                                    blurRadius: 12,
                                  ),
                                ]
                              : null,
                        ),
                        child: Icon(
                          selected ? item.selectedIcon : item.icon,
                          color: selected ? ironGreen : Colors.white54,
                          size: 22,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        item.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: selected ? ironGreen : Colors.white60,
                          fontWeight:
                              selected ? FontWeight.w800 : FontWeight.w600,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

class IronNavItem {
  final IconData icon;
  final IconData selectedIcon;
  final String label;

  const IronNavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });
}

class _IronCoreSpherePainter extends CustomPainter {
  final double progress;
  final IronCoreState state;

  const _IronCoreSpherePainter({
    required this.progress,
    required this.state,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide * 0.455;
    final stateColor = _ironCoreStateColor(state);
    final energy = _ironCoreEnergy(state);
    final cycle = progress * math.pi * 2;

    final auraPaint = Paint()
      ..color = stateColor.withOpacity(0.16 + energy * 0.12)
      ..maskFilter = MaskFilter.blur(
        BlurStyle.normal,
        18 + energy * 11,
      );
    canvas.drawCircle(center, radius * (0.94 + progress * 0.025), auraPaint);

    final sphereRect = Rect.fromCircle(center: center, radius: radius);
    final spherePaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.34, -0.42),
        radius: 1.12,
        colors: [
          Colors.white.withOpacity(0.12 + energy * 0.04),
          stateColor.withOpacity(0.15 + energy * 0.08),
          const Color(0xFF00190B).withOpacity(0.98),
          const Color(0xFF000402),
        ],
        stops: const [0.0, 0.22, 0.66, 1.0],
      ).createShader(sphereRect);
    canvas.drawCircle(center, radius, spherePaint);

    final orbitPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 1.2 + energy * 0.8
      ..shader = SweepGradient(
        transform: GradientRotation(cycle * 0.36),
        colors: [
          Colors.transparent,
          stateColor.withOpacity(0.18),
          stateColor.withOpacity(0.84),
          Colors.white.withOpacity(0.65),
          Colors.transparent,
        ],
        stops: const [0.0, 0.26, 0.47, 0.54, 0.72],
      ).createShader(sphereRect);

    for (var index = 0; index < 3; index++) {
      final orbitRadius = radius * (0.68 + index * 0.115);
      final rect = Rect.fromCircle(center: center, radius: orbitRadius);
      canvas.drawArc(
        rect,
        cycle * (index.isEven ? 0.28 : -0.22) + index * 1.7,
        math.pi * (0.30 + index * 0.07),
        false,
        orbitPaint,
      );
    }

    final particlePaint = Paint()..style = PaintingStyle.fill;
    for (var index = 0; index < 14; index++) {
      final angle = cycle * (0.08 + index % 3 * 0.025) +
          index * math.pi * 2 / 14;
      final particleRadius = radius * (0.62 + (index % 4) * 0.075);
      final flicker = (math.sin(cycle * 1.7 + index * 1.9) + 1) * 0.5;
      particlePaint.color = stateColor.withOpacity(
        0.10 + flicker * (0.18 + energy * 0.18),
      );
      canvas.drawCircle(
        center + Offset(
          math.cos(angle) * particleRadius,
          math.sin(angle) * particleRadius * 0.88,
        ),
        0.8 + flicker * 1.2,
        particlePaint,
      );
    }

    if (state == IronCoreState.listening) {
      final pulsePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = stateColor.withOpacity(0.46 - progress * 0.26);
      canvas.drawCircle(
        center,
        radius * (0.72 + progress * 0.20),
        pulsePaint,
      );
    } else if (state == IronCoreState.speaking) {
      final voicePaint = Paint()
        ..color = stateColor.withOpacity(0.58)
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 1.5;
      for (var index = 0; index < 24; index++) {
        final angle = index * math.pi * 2 / 24;
        final wave = (math.sin(cycle * 2.2 + index * 0.92) + 1) * 0.5;
        final start = radius * 0.74;
        final end = start + 3 + wave * radius * 0.07;
        canvas.drawLine(
          center + Offset(math.cos(angle) * start, math.sin(angle) * start),
          center + Offset(math.cos(angle) * end, math.sin(angle) * end),
          voicePaint,
        );
      }
    } else if (state == IronCoreState.thinking) {
      final nodePaint = Paint()
        ..color = stateColor.withOpacity(0.84)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5);
      for (var index = 0; index < 3; index++) {
        final angle = cycle * (0.72 + index * 0.11) + index * 2.1;
        canvas.drawCircle(
          center + Offset(
            math.cos(angle) * radius * (0.66 + index * 0.10),
            math.sin(angle) * radius * (0.66 + index * 0.10),
          ),
          2.2 + index * 0.4,
          nodePaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _IronCoreSpherePainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.state != state;
}

class _IronCoreGlassPainter extends CustomPainter {
  final double progress;
  final IronCoreState state;

  const _IronCoreGlassPainter({
    required this.progress,
    required this.state,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide * 0.455;
    final stateColor = _ironCoreStateColor(state);
    final sphereRect = Rect.fromCircle(center: center, radius: radius);

    final edgePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..shader = SweepGradient(
        transform: GradientRotation(progress * math.pi * 0.32),
        colors: [
          stateColor.withOpacity(0.12),
          Colors.white.withOpacity(0.72),
          stateColor.withOpacity(0.72),
          Colors.transparent,
          stateColor.withOpacity(0.12),
        ],
      ).createShader(sphereRect);
    canvas.drawCircle(center, radius, edgePaint);

    final highlightRect = Rect.fromCenter(
      center: Offset(size.width * 0.41, size.height * 0.30),
      width: size.width * 0.40,
      height: size.height * 0.13,
    );
    final highlightPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          Colors.white.withOpacity(0.17),
          Colors.white.withOpacity(0.015),
        ],
      ).createShader(highlightRect);
    canvas.drawOval(highlightRect, highlightPaint);

    final lowerShade = Paint()
      ..color = Colors.black.withOpacity(0.30)
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.shortestSide * 0.055
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius * 0.88),
      math.pi * 0.13,
      math.pi * 0.74,
      false,
      lowerShade,
    );
  }

  @override
  bool shouldRepaint(covariant _IronCoreGlassPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.state != state;
}

class _IronCorePedestalPainter extends CustomPainter {
  final double progress;
  final IronCoreState state;

  const _IronCorePedestalPainter({
    required this.progress,
    required this.state,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final color = _ironCoreStateColor(state);
    final center = Offset(size.width / 2, size.height * 0.62);
    final cycle = progress * math.pi * 2;
    final glow = 0.42 + (math.sin(cycle) + 1) * 0.11;

    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.34)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14);
    canvas.drawOval(
      Rect.fromCenter(
        center: center.translate(0, size.height * 0.12),
        width: size.width * 0.86,
        height: size.height * 0.38,
      ),
      shadowPaint,
    );

    final basePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3
      ..shader = LinearGradient(
        colors: [
          Colors.transparent,
          color.withOpacity(glow),
          Colors.white.withOpacity(0.32),
          color.withOpacity(glow),
          Colors.transparent,
        ],
      ).createShader(Offset.zero & size);

    for (var index = 0; index < 3; index++) {
      final width = size.width * (0.58 + index * 0.14);
      final height = size.height * (0.24 + index * 0.055);
      canvas.drawOval(
        Rect.fromCenter(center: center, width: width, height: height),
        basePaint,
      );
    }

    final beamPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          color.withOpacity(0.00),
          color.withOpacity(0.13),
          color.withOpacity(0.00),
        ],
      ).createShader(Offset.zero & size);

    final beamPath = Path()
      ..moveTo(size.width * 0.31, 0)
      ..lineTo(size.width * 0.69, 0)
      ..lineTo(size.width * 0.58, center.dy)
      ..lineTo(size.width * 0.42, center.dy)
      ..close();
    canvas.drawPath(beamPath, beamPaint);
  }

  @override
  bool shouldRepaint(covariant _IronCorePedestalPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.state != state;
}

class _PanelAccentPainter extends CustomPainter {
  final Color color;

  const _PanelAccentPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withOpacity(0.62)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    final path = Path()
      ..moveTo(15, 1)
      ..lineTo(math.min(size.width * 0.34, 105), 1)
      ..moveTo(size.width - 1, size.height * 0.58)
      ..lineTo(size.width - 1, size.height - 16)
      ..quadraticBezierTo(
        size.width - 1,
        size.height - 1,
        size.width - 16,
        size.height - 1,
      )
      ..lineTo(size.width * 0.72, size.height - 1);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _PanelAccentPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _HudBackgroundPainter extends CustomPainter {
  const _HudBackgroundPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = ironGreen.withOpacity(0.022)
      ..strokeWidth = 0.8;
    const step = 36.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final hudPaint = Paint()
      ..color = ironGreen.withOpacity(0.055)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawCircle(
      Offset(size.width * 0.5, size.height * 0.14),
      size.width * 0.34,
      hudPaint,
    );
    canvas.drawCircle(
      Offset(size.width * 0.5, size.height * 0.14),
      size.width * 0.27,
      hudPaint,
    );

    final wave = Path()..moveTo(0, size.height * 0.34);
    for (double x = 0; x <= size.width; x += 5) {
      final y = size.height * 0.34 +
          math.sin(x / 18) * 3 +
          math.sin(x / 7) * 1.2;
      wave.lineTo(x, y);
    }
    canvas.drawPath(wave, hudPaint);

    final watermarkPaint = Paint()
      ..color = ironGreen.withOpacity(0.035)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    _drawTinyLeaf(
      canvas,
      Offset(size.width * 0.09, size.height * 0.58),
      18,
      watermarkPaint,
    );
    _drawTinyLeaf(
      canvas,
      Offset(size.width * 0.91, size.height * 0.79),
      22,
      watermarkPaint,
    );
  }

  void _drawTinyLeaf(
    Canvas canvas,
    Offset center,
    double radius,
    Paint paint,
  ) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    for (final angle in [-1.0, -0.55, 0.0, 0.55, 1.0]) {
      canvas.save();
      canvas.rotate(angle);
      final path = Path()
        ..moveTo(0, radius * 0.25)
        ..quadraticBezierTo(-radius * 0.24, -radius * 0.1, 0, -radius)
        ..quadraticBezierTo(radius * 0.24, -radius * 0.1, 0, radius * 0.25);
      canvas.drawPath(path, paint);
      canvas.restore();
    }
    canvas.drawLine(Offset.zero, Offset(0, radius * 0.7), paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _HudCorePainter extends CustomPainter {
  final double progress;

  const _HudCorePainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..color = ironGreen.withOpacity(0.18 + progress * 0.18);

    canvas.drawCircle(center, radius * 0.92, ringPaint);
    canvas.drawCircle(center, radius * 0.81, ringPaint);
    canvas.drawCircle(center, radius * 0.68, ringPaint);

    final arcPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 3
      ..shader = SweepGradient(
        colors: [
          Colors.transparent,
          ironGreen.withOpacity(0.8),
          ironGreenSoft,
          Colors.transparent,
        ],
        stops: const [0.0, 0.36, 0.52, 0.72],
      ).createShader(Rect.fromCircle(center: center, radius: radius));

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius * 0.9),
      -math.pi * 0.8 + progress * 0.4,
      math.pi * 0.86,
      false,
      arcPaint,
    );
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius * 0.74),
      math.pi * 0.22 - progress * 0.3,
      math.pi * 0.58,
      false,
      arcPaint,
    );

    final tickPaint = Paint()
      ..color = ironGreen.withOpacity(0.32)
      ..strokeWidth = 1;
    for (var i = 0; i < 40; i++) {
      final angle = i * math.pi * 2 / 40;
      final longTick = i % 5 == 0;
      final r1 = radius * (longTick ? 0.82 : 0.86);
      final r2 = radius * 0.91;
      canvas.drawLine(
        center + Offset(math.cos(angle) * r1, math.sin(angle) * r1),
        center + Offset(math.cos(angle) * r2, math.sin(angle) * r2),
        tickPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _HudCorePainter oldDelegate) =>
      oldDelegate.progress != progress;
}
