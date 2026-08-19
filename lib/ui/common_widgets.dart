import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';

const ironGreen = Color(0xFF00FF66);
const ironGreenSoft = Color(0xFF37FF88);
const ironGreenDeep = Color(0xFF008F43);
const ironDark = Color(0xFF010603);
const ironPanel = Color(0xFF031108);
const ironPanelRaised = Color(0xFF061A0D);
const ironLine = Color(0xFF0A3A1C);
const ironGraphite = Color(0xFF0A0E0C);
const ironMist = Color(0xFF9CB4A5);

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
          center: Alignment(0.0, -0.92),
          radius: 1.62,
          colors: [
            Color(0xFF052413),
            ironGraphite,
            Color(0xFF000603),
            Colors.black,
          ],
          stops: [0.0, 0.28, 0.68, 1.0],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (showHud)
            IgnorePointer(
              child: Opacity(
                opacity: 0.72,
                child: CustomPaint(painter: _HudBackgroundPainter()),
              ),
            ),
          IgnorePointer(
            child: Align(
              alignment: const Alignment(0, -0.72),
              child: Container(
                width: 330,
                height: 330,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      ironGreen.withOpacity(0.040),
                      ironGreenDeep.withOpacity(0.012),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.55, 1.0],
                  ),
                ),
              ),
            ),
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
    final radius = borderRadius ?? BorderRadius.circular(16);
    return Container(
      width: double.infinity,
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: ironGreen.withOpacity(bright ? 0.12 : 0.045),
            blurRadius: bright ? 22 : 14,
            spreadRadius: bright ? 1 : 0,
          ),
          const BoxShadow(
            color: Colors.black45,
            blurRadius: 14,
            offset: Offset(0, 7),
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
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: ironGreen.withOpacity(0.29)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
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
    final radius = BorderRadius.circular(compact ? 13 : 15);
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

class CannabisCore extends StatefulWidget {
  final double progress;
  final double size;

  const CannabisCore({
    super.key,
    required this.progress,
    this.size = 300,
  });

  @override
  State<CannabisCore> createState() => _CannabisCoreState();
}

class _CannabisCoreState extends State<CannabisCore> {
  StreamSubscription<GyroscopeEvent>? _gyroscopeSubscription;
  DateTime? _lastGyroscopeUpdate;
  double _tiltX = 0.0;
  double _tiltY = 0.0;
  double _tiltZ = 0.0;

  @override
  void initState() {
    super.initState();
    try {
      _gyroscopeSubscription = gyroscopeEventStream(
        samplingPeriod: const Duration(milliseconds: 32),
      ).listen(
        _handleGyroscope,
        onError: (_) {},
        cancelOnError: false,
      );
    } catch (_) {
      _gyroscopeSubscription = null;
    }
  }

  void _handleGyroscope(GyroscopeEvent event) {
    if (!mounted) return;

    final now = DateTime.now();
    final previous = _lastGyroscopeUpdate;
    _lastGyroscopeUpdate = now;
    final dt = previous == null
        ? 0.032
        : (now.difference(previous).inMicroseconds / 1000000.0)
            .clamp(0.008, 0.080)
            .toDouble();

    const dampingXY = 0.88;
    const dampingZ = 0.84;
    const gainXY = 0.74;
    const gainZ = 0.34;

    final nextX = ((_tiltX * dampingXY) - event.x * dt * gainXY)
        .clamp(-0.165, 0.165)
        .toDouble();
    final nextY = ((_tiltY * dampingXY) + event.y * dt * gainXY)
        .clamp(-0.165, 0.165)
        .toDouble();
    final nextZ = ((_tiltZ * dampingZ) + event.z * dt * gainZ)
        .clamp(-0.080, 0.080)
        .toDouble();

    if ((nextX - _tiltX).abs() < 0.00035 &&
        (nextY - _tiltY).abs() < 0.00035 &&
        (nextZ - _tiltZ).abs() < 0.00035) {
      return;
    }

    setState(() {
      _tiltX = nextX;
      _tiltY = nextY;
      _tiltZ = nextZ;
    });
  }

  @override
  void dispose() {
    _gyroscopeSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress = widget.progress;
    final size = widget.size;
    final breathe = 0.985 + progress * 0.030;
    final motion = ((_tiltX.abs() + _tiltY.abs()) / 0.33)
        .clamp(0.0, 1.0)
        .toDouble();
    final glow = 0.14 + progress * 0.16 + motion * 0.10;
    final idleTiltX = (progress - 0.5) * 0.016;
    final idleTiltY = (0.5 - progress) * 0.022;
    final lightX = (_tiltY * 4.1).clamp(-0.75, 0.75).toDouble();
    final lightY = (-_tiltX * 4.1).clamp(-0.75, 0.75).toDouble();
    final depthOffset = Offset(
      _tiltY * size * 0.075,
      -_tiltX * size * 0.075,
    );

    Widget exactLeaf({double opacity = 1.0}) {
      return Opacity(
        opacity: opacity,
        child: Image.asset(
          'assets/images/hud_core_exact.png',
          width: size * 0.88,
          height: size * 0.88,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
          errorBuilder: (context, error, stackTrace) => CustomPaint(
            size: Size.square(size),
            painter: _HudCorePainter(progress: progress),
          ),
        ),
      );
    }

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Transform.translate(
            offset: depthOffset * 0.28,
            child: Transform.scale(
              scale: 0.94 + progress * 0.030 + motion * 0.014,
              child: Container(
                width: size * 0.88,
                height: size * 0.88,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    center: Alignment(-0.34 + lightX * 0.30, -0.42 + lightY * 0.30),
                    colors: [
                      Colors.white.withOpacity(0.10 + progress * 0.04),
                      ironGreen.withOpacity(0.13 + progress * 0.07 + motion * 0.04),
                      const Color(0xFF021109).withOpacity(0.90),
                      Colors.black.withOpacity(0.08),
                    ],
                    stops: const [0.0, 0.18, 0.62, 1.0],
                  ),
                  border: Border.all(
                    color: ironGreen.withOpacity(0.22 + progress * 0.10),
                    width: 1.2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: ironGreen.withOpacity(
                        glow.clamp(0.0, 0.42).toDouble(),
                      ),
                      blurRadius: 30 + progress * 18 + motion * 12,
                      spreadRadius: 1 + progress * 2 + motion * 1.4,
                    ),
                    BoxShadow(
                      color: Colors.black.withOpacity(0.78),
                      blurRadius: 28 + motion * 8,
                      offset: Offset(
                        -depthOffset.dx * 0.22,
                        14 - depthOffset.dy * 0.22,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          IgnorePointer(
            child: Transform.translate(
              offset: depthOffset * -0.10,
              child: CustomPaint(
                size: Size.square(size * 0.94),
                painter: _CoreOrbitPainter(
                  progress: progress,
                  motion: motion,
                  lightX: lightX,
                ),
              ),
            ),
          ),
          Transform.translate(
            offset: depthOffset,
            child: Transform.scale(
              scale: breathe + motion * 0.010,
              child: Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()
                  ..setEntry(3, 2, 0.0019)
                  ..rotateX(_tiltX + idleTiltX)
                  ..rotateY(_tiltY + idleTiltY)
                  ..rotateZ(_tiltZ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Opacity(
                      opacity: 0.78,
                      child: exactLeaf(),
                    ),
                    Opacity(
                      opacity: (0.08 + progress * 0.16 + motion * 0.14)
                          .clamp(0.0, 0.36)
                          .toDouble(),
                      child: ShaderMask(
                        blendMode: BlendMode.srcATop,
                        shaderCallback: (bounds) => LinearGradient(
                          begin: Alignment(-0.95 + lightX, 0.95 + lightY),
                          end: Alignment(0.85 + lightX, -0.95 + lightY),
                          colors: const [
                            Colors.transparent,
                            Color(0xFFC9FFD9),
                            Color(0xFF55FF94),
                            Colors.transparent,
                          ],
                          stops: const [0.04, 0.40, 0.56, 0.94],
                        ).createShader(bounds),
                        child: exactLeaf(),
                      ),
                    ),
                    IgnorePointer(
                      child: CustomPaint(
                        size: Size.square(size * 0.56),
                        painter: _LiveLeafVeinPainter(
                          progress: progress,
                          motion: motion,
                          lightX: lightX,
                          lightY: lightY,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          IgnorePointer(
            child: Transform.translate(
              offset: depthOffset * -0.18,
              child: Container(
                width: size * 0.76,
                height: size * 0.76,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withOpacity(
                      0.028 + progress * 0.040 + motion * 0.020,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CoreOrbitPainter extends CustomPainter {
  final double progress;
  final double motion;
  final double lightX;

  const _CoreOrbitPainter({
    required this.progress,
    required this.motion,
    required this.lightX,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide * 0.43;
    final basePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 1.0
      ..color = ironGreen.withOpacity(0.12 + progress * 0.08);

    canvas.drawCircle(center, radius * 0.86, basePaint);
    canvas.drawCircle(
      center,
      radius * 1.03,
      basePaint..color = ironMist.withOpacity(0.055 + motion * 0.05),
    );

    for (var i = 0; i < 3; i++) {
      final sweep = math.pi * (0.34 + i * 0.08 + progress * 0.10);
      final start = progress * math.pi * 2 + i * 1.82 + lightX * 0.35;
      final rect = Rect.fromCircle(
        center: center,
        radius: radius * (0.72 + i * 0.15),
      );
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = i == 1 ? 2.3 : 1.4
        ..shader = SweepGradient(
          colors: [
            Colors.transparent,
            ironGreen.withOpacity(0.18 + progress * 0.18),
            ironGreenSoft.withOpacity(0.34 + motion * 0.16),
            Colors.transparent,
          ],
          stops: const [0.0, 0.40, 0.58, 1.0],
          transform: GradientRotation(start),
        ).createShader(rect);
      canvas.drawArc(rect, start, sweep, false, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _CoreOrbitPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.motion != motion ||
        oldDelegate.lightX != lightX;
  }
}

class _LiveLeafVeinPainter extends CustomPainter {
  final double progress;
  final double motion;
  final double lightX;
  final double lightY;

  const _LiveLeafVeinPainter({
    required this.progress,
    required this.motion,
    required this.lightX,
    required this.lightY,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final pulse = 0.45 + 0.55 * math.sin(progress * math.pi * 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = 1.1 + pulse * 0.7 + motion * 0.45
      ..color = ironGreenSoft.withOpacity(0.26 + pulse * 0.28 + motion * 0.12)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.2);

    final highlight = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 0.65
      ..color = Colors.white.withOpacity(0.12 + pulse * 0.10);

    void drawLeaflet(double angle, double length, double spread) {
      canvas.save();
      canvas.translate(center.dx + lightX * 2.5, center.dy + lightY * 2.5);
      canvas.rotate(angle);
      final tip = Offset(0, -length);
      canvas.drawLine(Offset.zero, tip, paint);
      canvas.drawLine(Offset.zero, tip, highlight);

      for (var i = 1; i <= 4; i++) {
        final y = -length * (i / 5.4);
        final side = spread * (1.0 - i * 0.11);
        canvas.drawLine(Offset(0, y), Offset(-side, y - length * 0.105), paint);
        canvas.drawLine(Offset(0, y), Offset(side, y - length * 0.105), paint);
      }
      canvas.restore();
    }

    drawLeaflet(0, size.height * 0.48, size.width * 0.060);
    drawLeaflet(-0.48, size.height * 0.41, size.width * 0.054);
    drawLeaflet(0.48, size.height * 0.41, size.width * 0.054);
    drawLeaflet(-0.92, size.height * 0.34, size.width * 0.046);
    drawLeaflet(0.92, size.height * 0.34, size.width * 0.046);
    drawLeaflet(-1.34, size.height * 0.25, size.width * 0.036);
    drawLeaflet(1.34, size.height * 0.25, size.width * 0.036);

    final stemPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2.1
      ..color = ironGreenSoft.withOpacity(0.18 + pulse * 0.16);
    canvas.drawLine(
      center + Offset(lightX * 2.5, lightY * 2.5),
      center + Offset(lightX * 2.5, size.height * 0.42 + lightY * 2.5),
      stemPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _LiveLeafVeinPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.motion != motion ||
        oldDelegate.lightX != lightX ||
        oldDelegate.lightY != lightY;
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
      margin: const EdgeInsets.fromLTRB(10, 0, 10, 8),
      decoration: BoxDecoration(
        color: const Color(0xFF020907).withOpacity(0.985),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: ironGreen.withOpacity(0.18)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.56),
            blurRadius: 18,
            offset: const Offset(0, -2),
          ),
          BoxShadow(
            color: ironGreen.withOpacity(0.035),
            blurRadius: 18,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 64,
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
                          curve: Curves.easeOutCubic,
                          width: selected ? 54 : 42,
                          height: 33,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(15),
                            gradient: selected
                                ? LinearGradient(
                                    colors: [
                                      ironGreen.withOpacity(0.16),
                                      ironGreenDeep.withOpacity(0.06),
                                    ],
                                  )
                                : null,
                            border: Border.all(
                              color: selected
                                  ? ironGreen.withOpacity(0.34)
                                  : Colors.transparent,
                            ),
                            boxShadow: selected
                                ? [
                                    BoxShadow(
                                      color: ironGreen.withOpacity(0.10),
                                      blurRadius: 12,
                                    ),
                                  ]
                                : null,
                          ),
                          child: Icon(
                            selected ? item.selectedIcon : item.icon,
                            color: selected ? ironGreenSoft : Colors.white38,
                            size: selected ? 23 : 21,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          item.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: selected ? ironGreen : Colors.white38,
                            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                            fontSize: 9.2,
                            letterSpacing: selected ? 0.15 : 0,
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

class _HudBackgroundPainter extends CustomPainter {
  const _HudBackgroundPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = ironGreen.withOpacity(0.014)
      ..strokeWidth = 0.8;
    const step = 36.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final hudPaint = Paint()
      ..color = ironGreen.withOpacity(0.036)
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

class _CannabisLeafPainter extends CustomPainter {
  final double glow;

  const _CannabisLeafPainter({required this.glow});

  Path _serratedLeaflet({
    required double length,
    required double width,
    required int teeth,
  }) {
    final path = Path()..moveTo(0, 0);
    final steps = teeth * 2 + 2;

    for (var i = 1; i < steps; i++) {
      final t = i / steps;
      final envelope = math.pow(math.sin(math.pi * t), 0.72).toDouble();
      final serration = i.isEven ? 1.0 : 0.58;
      path.lineTo(-width * envelope * serration, -length * t);
    }

    path.lineTo(0, -length);

    for (var i = steps - 1; i >= 1; i--) {
      final t = i / steps;
      final envelope = math.pow(math.sin(math.pi * t), 0.72).toDouble();
      final serration = i.isEven ? 1.0 : 0.58;
      path.lineTo(width * envelope * serration, -length * t);
    }

    return path..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.79);
    final scale = size.shortestSide;

    final glowPaint = Paint()
      ..color = ironGreen.withOpacity(0.20 + glow * 0.14)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
    final fillPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: [
          Color(0xFF00451F),
          Color(0xFF00C95A),
          Color(0xFF33FF88),
        ],
      ).createShader(Offset.zero & size);
    final outlinePaint = Paint()
      ..color = const Color(0xFF8CFFB4).withOpacity(0.98)
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = math.max(1.0, scale * 0.012);
    final veinPaint = Paint()
      ..color = const Color(0xFFB8FFD0).withOpacity(0.62)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.max(0.7, scale * 0.0065);

    final leaflets = <({double angle, double length, double width, int teeth})>[
      (angle: -0.96, length: 0.39, width: 0.050, teeth: 3),
      (angle: -0.64, length: 0.56, width: 0.068, teeth: 4),
      (angle: -0.33, length: 0.72, width: 0.082, teeth: 5),
      (angle: 0.00, length: 0.86, width: 0.090, teeth: 6),
      (angle: 0.33, length: 0.72, width: 0.082, teeth: 5),
      (angle: 0.64, length: 0.56, width: 0.068, teeth: 4),
      (angle: 0.96, length: 0.39, width: 0.050, teeth: 3),
    ];

    for (final leaflet in leaflets) {
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(leaflet.angle);

      final length = scale * leaflet.length;
      final width = scale * leaflet.width;
      final path = _serratedLeaflet(
        length: length,
        width: width,
        teeth: leaflet.teeth,
      );

      canvas.drawPath(path, glowPaint);
      canvas.drawPath(path, fillPaint);
      canvas.drawPath(path, outlinePaint);
      canvas.drawLine(Offset.zero, Offset(0, -length * 0.96), veinPaint);

      for (var tooth = 1; tooth <= leaflet.teeth; tooth++) {
        final t = tooth / (leaflet.teeth + 1);
        final envelope = math.pow(math.sin(math.pi * t), 0.72).toDouble();
        final x = width * envelope * 0.82;
        final y = -length * t;
        canvas.drawLine(
          Offset(0, y + length * 0.035),
          Offset(-x, y - length * 0.025),
          veinPaint,
        );
        canvas.drawLine(
          Offset(0, y + length * 0.035),
          Offset(x, y - length * 0.025),
          veinPaint,
        );
      }

      canvas.restore();
    }

    final stemGlow = Paint()
      ..color = ironGreen.withOpacity(0.32)
      ..strokeWidth = math.max(4, scale * 0.034)
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7);
    final stemPaint = Paint()
      ..color = const Color(0xFF59FF96)
      ..strokeWidth = math.max(1.8, scale * 0.017)
      ..strokeCap = StrokeCap.round;

    final stemStart = center.translate(0, -scale * 0.025);
    final stemEnd = center.translate(0, scale * 0.19);
    canvas.drawLine(stemStart, stemEnd, stemGlow);
    canvas.drawLine(stemStart, stemEnd, stemPaint);
  }

  @override
  bool shouldRepaint(covariant _CannabisLeafPainter oldDelegate) =>
      oldDelegate.glow != glow;
}
