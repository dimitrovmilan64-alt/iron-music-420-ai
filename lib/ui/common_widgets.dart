import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/iron_theme.dart';

export '../theme/iron_theme.dart';

const ironPanel = ironSurface;
const ironPanelRaised = ironSurfaceHigh;

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
    this.showHud = false,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF0C1610),
            ironDark,
            Color(0xFF050806),
          ],
        ),
      ),
      child: _ViewSafeArea(child: child),
    );
  }
}

/// Uses viewPadding so Android 15 edge-to-edge still insets after Scaffold
/// has already consumed MediaQuery.padding.
class _ViewSafeArea extends StatelessWidget {
  final Widget child;
  const _ViewSafeArea({required this.child});

  @override
  Widget build(BuildContext context) {
    final view = MediaQuery.viewPaddingOf(context);
    final padding = MediaQuery.paddingOf(context);
    final top = view.top > padding.top ? view.top - padding.top : padding.top;
    final bottom = view.bottom > padding.bottom ? 0.0 : 0.0;
    // Horizontal insets (notches) should still apply.
    final left = view.left > padding.left ? view.left : padding.left;
    final right = view.right > padding.right ? view.right : padding.right;
    return Padding(
      padding: EdgeInsets.fromLTRB(left, top, right, bottom),
      child: child,
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
                  eyebrow!,
                  style: const TextStyle(
                    color: ironMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 6),
              ],
              Text(
                title,
                style: ironText(
                  size: 32,
                  weight: FontWeight.w800,
                  height: 1.05,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                subtitle,
                style: const TextStyle(
                  color: ironMuted,
                  fontSize: 14,
                  height: 1.35,
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

  final bool accent;

  const IronCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin = const EdgeInsets.only(bottom: 16),
    this.bright = false,
    this.accent = false,
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
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: bright ? const Color(0xFF151C18) : ironSurfaceHigh,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: ironBorderSide(accent: accent, strong: accent),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: padding,
          child: child,
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
        labelText: label.isEmpty ? null : label,
        hintText: hint,
        prefixIcon: icon == null ? null : Icon(icon, color: ironGreen),
        labelStyle: const TextStyle(
          color: ironMuted,
          fontWeight: FontWeight.w600,
        ),
        floatingLabelStyle: const TextStyle(
          color: ironGreenSoft,
          fontWeight: FontWeight.w700,
        ),
        hintStyle: const TextStyle(color: Colors.white30),
        filled: true,
        fillColor: ironSurface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: ironHairline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: ironGreen, width: 1.4),
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
                      color: ironHairline.withOpacity(enabled ? 1 : 0.5),
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
            ? ironGreen.withValues(alpha: 0.14)
            : ironSurface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          width: 1,
          color: ironGreen.withValues(alpha: active ? 0.75 : 0.38),
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

class CannabisCore extends StatelessWidget {
  final double progress;
  final double size;

  const CannabisCore({
    super.key,
    required this.progress,
    this.size = 300,
  });

  @override
  Widget build(BuildContext context) {
    final pulse = 0.92 + progress * 0.08;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Transform.scale(
            scale: pulse,
            child: Container(
              width: size * 0.88,
              height: size * 0.88,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: ironGreen.withOpacity(0.08 + progress * 0.06),
                    blurRadius: 12 + progress * 6,
                    spreadRadius: 0,
                  ),
                ],
              ),
            ),
          ),
          Transform.rotate(
            angle: (progress - 0.5) * math.pi * 0.012,
            child: Image.asset(
              'assets/images/hud_core_exact.png',
              width: size,
              height: size,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.medium,
              errorBuilder: (context, error, stackTrace) => CustomPaint(
                size: Size.square(size),
                painter: _HudCorePainter(progress: progress),
              ),
            ),
          ),
          IgnorePointer(
            child: Container(
              width: size * 0.79,
              height: size * 0.79,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withOpacity(0.05 + progress * 0.04),
                ),
              ),
            ),
          ),
        ],
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
      ..quadraticBezierTo(size.width - 1, size.height - 1, size.width - 16, size.height - 1)
      ..lineTo(size.width * 0.72, size.height - 1);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _PanelAccentPainter oldDelegate) =>
      oldDelegate.color != color;
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
