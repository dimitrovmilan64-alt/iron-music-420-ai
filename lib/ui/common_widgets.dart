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

const double _ironCoreLeafScale = 0.76;

Offset _ironLeafRoot(Size size) {
  return Offset(size.width * 0.50, size.height * 0.79);
}

List<Offset> _ironLeafTipTargets(Size size) {
  return [
    Offset(size.width * 0.50, size.height * 0.04),
    Offset(size.width * 0.35, size.height * 0.14),
    Offset(size.width * 0.21, size.height * 0.31),
    Offset(size.width * 0.12, size.height * 0.53),
    Offset(size.width * 0.65, size.height * 0.14),
    Offset(size.width * 0.79, size.height * 0.31),
    Offset(size.width * 0.88, size.height * 0.53),
  ];
}

Path _ironCannabisLeafSilhouette(Size size) {
  final root = _ironLeafRoot(size);
  final targets = _ironLeafTipTargets(size);
  final widths = <double>[
    0.060,
    0.070,
    0.074,
    0.064,
    0.070,
    0.074,
    0.064,
  ];

  var combined = _ironCannabisLeaflet(root, targets.first, widths.first);
  for (var i = 1; i < targets.length; i++) {
    combined = Path.combine(
      PathOperation.union,
      combined,
      _ironCannabisLeaflet(root, targets[i], widths[i]),
    );
  }

  final stem = Path()
    ..addRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(size.width * 0.50, size.height * 0.89),
          width: size.width * 0.020,
          height: size.height * 0.18,
        ),
        Radius.circular(size.width * 0.010),
      ),
    );
  return Path.combine(PathOperation.union, combined, stem);
}

Path _ironCannabisLeaflet(Offset root, Offset tip, double widthFactor) {
  final direction = root - tip;
  final length = direction.distance;
  if (length == 0) return Path();
  final unit = direction / length;
  final normal = Offset(-unit.dy, unit.dx);
  final maxWidth = length * widthFactor;
  const steps = 24;

  final rightEdge = <Offset>[];
  final leftEdge = <Offset>[];
  for (var i = 0; i <= steps; i++) {
    final t = i / steps;
    final spine = Offset.lerp(tip, root, t)!;
    final profile = math.pow(math.sin(t * math.pi), 0.82).toDouble();
    final serration = i.isEven ? 1.0 : 0.86;
    final width = maxWidth * profile * serration;
    rightEdge.add(spine + normal * width);
    leftEdge.add(spine - normal * width);
  }

  final path = Path()
    ..moveTo(tip.dx, tip.dy);
  for (var i = 1; i < rightEdge.length; i++) {
    path.lineTo(rightEdge[i].dx, rightEdge[i].dy);
  }
  for (var i = leftEdge.length - 2; i >= 0; i--) {
    path.lineTo(leftEdge[i].dx, leftEdge[i].dy);
  }
  return path..close();
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
    final leafPulse =
        0.992 + math.sin(cycle * 1.35) * (0.006 + energy * 0.010);
    final leafTurn = math.sin(cycle * 0.44) * 0.045;
    return RepaintBoundary(
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _IronCoreMachineRingPainter(
                  progress: progress,
                  state: state,
                ),
              ),
            ),
            Positioned.fill(
              child: CustomPaint(
                painter: _IronCoreSpherePainter(
                  progress: progress,
                  state: state,
                ),
              ),
            ),
            Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.0009)
                ..rotateX(-0.10)
                ..rotateY(leafTurn),
              child: Transform.translate(
                offset: Offset(0, size * 0.018),
                child: Transform.scale(
                  scale: breath,
                  child: IgnorePointer(
                    child: CustomPaint(
                      size: Size.square(size * _ironCoreLeafScale),
                      painter: _IronCoreLeafPainter(
                        progress: progress,
                        state: state,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Transform.scale(
              scale: leafPulse,
              child: Transform.translate(
                offset: Offset(0, size * 0.018),
                child: IgnorePointer(
                  child: Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()
                      ..setEntry(3, 2, 0.0009)
                      ..rotateX(-0.10)
                      ..rotateY(leafTurn),
                    child: CustomPaint(
                      size: Size.square(size * _ironCoreLeafScale),
                      painter: _LivingLeafVeinPainter(
                        progress: progress,
                        state: state,
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

class _IronCoreMachineRingPainter extends CustomPainter {
  final double progress;
  final IronCoreState state;

  const _IronCoreMachineRingPainter({
    required this.progress,
    required this.state,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide * 0.465;
    final color = _ironCoreStateColor(state);
    final energy = _ironCoreEnergy(state);
    final cycle = progress * math.pi * 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final outerGlow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = radius * 0.035
      ..color = color.withOpacity(0.05 + energy * 0.035)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * 0.08);
    canvas.drawCircle(center, radius * 0.98, outerGlow);

    for (var layer = 0; layer < 5; layer++) {
      final layerRadius = radius * (0.70 + layer * 0.074);
      final layerRect = Rect.fromCircle(center: center, radius: layerRadius);
      final basePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.0, radius * (0.006 + layer * 0.001))
        ..color = color.withOpacity(0.08 + energy * 0.030);
      canvas.drawCircle(center, layerRadius, basePaint);

      final segmentPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.butt
        ..strokeWidth = radius * (0.012 + layer * 0.003)
        ..shader = SweepGradient(
          transform: GradientRotation(cycle * (layer.isEven ? 0.18 : -0.13)),
          colors: [
            Colors.transparent,
            color.withOpacity(0.16),
            Colors.white.withOpacity(0.42),
            color.withOpacity(0.72),
            Colors.transparent,
          ],
          stops: const [0.0, 0.24, 0.35, 0.48, 0.64],
        ).createShader(layerRect);

      final count = 9 + layer * 3;
      for (var i = 0; i < count; i++) {
        final start = cycle * (layer.isEven ? 0.05 : -0.04) +
            i * math.pi * 2 / count;
        final sweep = math.pi * (0.030 + (i % 4) * 0.008);
        canvas.drawArc(layerRect, start, sweep, false, segmentPaint);
      }
    }

    final tickPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.square
      ..strokeWidth = 1.0
      ..color = color.withOpacity(0.30 + energy * 0.16);
    for (var i = 0; i < 48; i++) {
      final angle = i * math.pi * 2 / 48 + cycle * 0.015;
      final longTick = i % 6 == 0;
      final inner = radius * (longTick ? 0.79 : 0.84);
      final outer = radius * 0.90;
      canvas.drawLine(
        center + Offset(math.cos(angle) * inner, math.sin(angle) * inner),
        center + Offset(math.cos(angle) * outer, math.sin(angle) * outer),
        tickPaint,
      );
    }

    final flarePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = radius * 0.010
      ..color = Colors.white.withOpacity(0.28 + energy * 0.12)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * 0.010);
    for (final angle in <double>[0, math.pi / 2, math.pi, math.pi * 1.5]) {
      canvas.drawArc(
        rect,
        angle + cycle * 0.03,
        math.pi * 0.035,
        false,
        flarePaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _IronCoreMachineRingPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.state != state;
  }
}

class _IronCoreLeafPainter extends CustomPainter {
  final double progress;
  final IronCoreState state;

  const _IronCoreLeafPainter({
    required this.progress,
    required this.state,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final energy = _ironCoreEnergy(state);
    final cycle = progress * math.pi * 2;
    final root = _ironLeafRoot(size);
    final leafPath = _ironCannabisLeafSilhouette(size);

    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.46)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, size.width * 0.035);
    canvas.drawPath(
      leafPath.shift(Offset(size.width * 0.018, size.height * 0.030)),
      shadowPaint,
    );

    final massGlowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round
      ..strokeWidth = size.width * 0.020
      ..color = const Color(0xFF49FF72).withOpacity(0.30 + energy * 0.08)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, size.width * 0.022);
    canvas.drawPath(leafPath, massGlowPaint);

    final bodyPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.32, -0.42),
        radius: 1.10,
        colors: [
          Colors.white.withOpacity(0.14),
          const Color(0xFF7BFF93).withOpacity(0.70 + energy * 0.07),
          const Color(0xFF079047).withOpacity(0.88),
          const Color(0xFF043D20).withOpacity(0.98),
        ],
        stops: const [0.0, 0.20, 0.58, 1.0],
      ).createShader(Offset.zero & size);
    canvas.drawPath(leafPath, bodyPaint);

    final innerShade = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withOpacity(0.08),
          Colors.transparent,
          Colors.black.withOpacity(0.34),
        ],
        stops: const [0.0, 0.42, 1.0],
      ).createShader(Offset.zero & size)
      ..blendMode = BlendMode.srcATop;
    canvas.drawPath(leafPath, innerShade);

    final rimPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round
      ..strokeWidth = size.width * 0.008
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withOpacity(0.45),
          const Color(0xFF73FF91).withOpacity(0.78),
          const Color(0xFF0D5A2B).withOpacity(0.58),
        ],
      ).createShader(Offset.zero & size);
    canvas.drawPath(leafPath, rimPaint);

    final midribPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = size.width * 0.009
      ..color = const Color(0xFFD5FFE0).withOpacity(0.50)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, size.width * 0.003);
    final fineVeinPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = size.width * 0.0028
      ..color = const Color(0xFFDBFFE4).withOpacity(0.28);

    final veinTargets = _ironLeafTipTargets(size);

    canvas.save();
    canvas.clipPath(leafPath);
    for (var i = 0; i < veinTargets.length; i++) {
      final target = veinTargets[i];
      final path = _veinPath(root, target, (target.dx - root.dx) * 0.00020);
      canvas.drawPath(path, i == 0 ? midribPaint : fineVeinPaint);
      _drawSideVeins(canvas, root, target, fineVeinPaint, size);
    }

    final lifeGlowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = size.width * (0.004 + energy * 0.002)
      ..color = const Color(0xFFB7FFC7)
          .withOpacity(0.16 + ((math.sin(cycle * 1.8) + 1) * 0.5) * 0.14)
      ..blendMode = BlendMode.plus
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, size.width * 0.004);
    canvas.drawPath(_veinPath(root, veinTargets.first, 0), lifeGlowPaint);
    canvas.restore();
  }

  void _drawSideVeins(
    Canvas canvas,
    Offset root,
    Offset tip,
    Paint paint,
    Size size,
  ) {
    final direction = tip - root;
    final length = direction.distance;
    if (length <= 0) return;
    final unit = direction / length;
    final normal = Offset(-unit.dy, unit.dx);
    final sides = (tip.dx - root.dx).abs() < size.width * 0.025
        ? const [-1.0, 1.0]
        : [tip.dx < root.dx ? -1.0 : 1.0];

    for (var j = 1; j <= 3; j++) {
      final base = root + direction * (0.24 + j * 0.14);
      final sideLength = length * (0.08 + j * 0.012);
      for (final sign in sides) {
        final branchTip = base + normal * sideLength * sign;
        final path = Path()
          ..moveTo(base.dx, base.dy)
          ..quadraticBezierTo(
            (base.dx + branchTip.dx) * 0.5 + unit.dx * size.width * 0.012,
            (base.dy + branchTip.dy) * 0.5 + unit.dy * size.width * 0.012,
            branchTip.dx,
            branchTip.dy,
          );
        canvas.drawPath(path, paint);
      }
    }
  }

  Path _veinPath(Offset root, Offset tip, double bend) {
    final control = Offset(
      (root.dx + tip.dx) * 0.5 + bend,
      (root.dy + tip.dy) * 0.5 - (root.dy - tip.dy).abs() * 0.08,
    );
    return Path()
      ..moveTo(root.dx, root.dy)
      ..quadraticBezierTo(control.dx, control.dy, tip.dx, tip.dy);
  }

  @override
  bool shouldRepaint(covariant _IronCoreLeafPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.state != state;
  }
}

class _LivingLeafVeinPainter extends CustomPainter {
  final double progress;
  final IronCoreState state;

  const _LivingLeafVeinPainter({
    required this.progress,
    required this.state,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final energy = _ironCoreEnergy(state);
    final cycle = progress * math.pi * 2;
    final root = _ironLeafRoot(size);
    final veinTargets = _ironLeafTipTargets(size);
    final pulse = 0.55 +
        ((math.sin(cycle * 2.6) + 1) * 0.5) * (0.28 + energy * 0.22);
    final sweep = (progress * 1.35) % 1.0;

    final leafMask = _ironCannabisLeafSilhouette(size);
    canvas.save();
    canvas.clipPath(leafMask);

    final glowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..blendMode = BlendMode.plus
      ..color = const Color(0xFF7EFF9A).withOpacity(0.045 + pulse * 0.085)
      ..strokeWidth = size.width * (0.0045 + energy * 0.0024)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, size.width * 0.005);

    final veinPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..blendMode = BlendMode.plus
      ..color = const Color(0xFFD8FFE1).withOpacity(0.10 + pulse * 0.15)
      ..strokeWidth = size.width * (0.0017 + energy * 0.0008);

    final hotPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..blendMode = BlendMode.plus
      ..shader = LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: [
          Colors.transparent,
          const Color(0xFFFFFFFF).withOpacity(0.03),
          const Color(0xFF74FF8D).withOpacity(0.25),
          Colors.transparent,
        ],
        stops: [
          (sweep - 0.22).clamp(0.0, 1.0).toDouble(),
          (sweep - 0.04).clamp(0.0, 1.0).toDouble(),
          sweep.clamp(0.0, 1.0).toDouble(),
          (sweep + 0.20).clamp(0.0, 1.0).toDouble(),
        ],
      ).createShader(Offset.zero & size)
      ..strokeWidth = size.width * (0.0022 + energy * 0.0012)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, size.width * 0.0025);

    final veins = <Path>[
      for (final target in veinTargets)
        _veinPath(root, target, (target.dx - root.dx) * 0.00022),
    ];

    for (var i = 0; i < veins.length; i++) {
      final local = 0.55 + ((math.sin(cycle * 2.0 + i * 0.9) + 1) * 0.5) * 0.45;
      final glow = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..blendMode = BlendMode.plus
        ..color = const Color(0xFF69FF86).withOpacity(0.035 + local * 0.075)
        ..strokeWidth = size.width * (0.0038 + local * 0.0015)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, size.width * 0.004);
      canvas.drawPath(veins[i], glow);
      canvas.drawPath(veins[i], veinPaint);
      _drawMovingPulse(canvas, veins[i], hotPaint, sweep + i * 0.075);
    }

    final sparkPaint = Paint()
      ..style = PaintingStyle.fill
      ..blendMode = BlendMode.plus
      ..color = const Color(0xFFC8FFD4).withOpacity(0.10 + energy * 0.12)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, size.width * 0.004);

    for (var i = 0; i < 5; i++) {
      final t = (progress * (0.55 + i * 0.08) + i * 0.137) % 1.0;
      final side = i.isEven ? -1.0 : 1.0;
      final x = root.dx +
          side * math.sin(t * math.pi) * size.width * (0.05 + i * 0.010);
      final y = root.dy - t * size.height * 0.37;
      final radius =
          size.width * (0.0018 + ((math.sin(cycle + i) + 1) * 0.5) * 0.0024);
      canvas.drawCircle(Offset(x, y), radius, sparkPaint);
    }
    canvas.restore();
  }

  Path _veinPath(Offset root, Offset tip, double bend) {
    final control = Offset(
      (root.dx + tip.dx) * 0.5 + (tip.dx - root.dx).abs() * bend,
      (root.dy + tip.dy) * 0.5 - (root.dy - tip.dy).abs() * 0.08,
    );
    return Path()
      ..moveTo(root.dx, root.dy)
      ..quadraticBezierTo(control.dx, control.dy, tip.dx, tip.dy);
  }

  void _drawMovingPulse(Canvas canvas, Path path, Paint paint, double phase) {
    final metric = path.computeMetrics().isEmpty
        ? null
        : path.computeMetrics().first;
    if (metric == null || metric.length <= 0) return;
    final t = phase % 1.0;
    final start = (t - 0.18).clamp(0.0, 1.0).toDouble() * metric.length;
    final end = (t + 0.05).clamp(0.0, 1.0).toDouble() * metric.length;
    if (end <= start) return;
    canvas.drawPath(metric.extractPath(start, end), paint);
  }

  @override
  bool shouldRepaint(covariant _LivingLeafVeinPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.state != state;
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

    final castShadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.58)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * 0.16);
    canvas.drawOval(
      Rect.fromCenter(
        center: center.translate(0, radius * 0.16),
        width: radius * 1.72,
        height: radius * 1.42,
      ),
      castShadowPaint,
    );

    final sphereRect = Rect.fromCircle(center: center, radius: radius);
    final spherePaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.38, -0.46),
        radius: 1.06,
        colors: [
          Colors.white.withOpacity(0.18 + energy * 0.05),
          stateColor.withOpacity(0.20 + energy * 0.10),
          const Color(0xFF003214).withOpacity(0.88),
          const Color(0xFF001007).withOpacity(0.98),
          const Color(0xFF000402),
        ],
        stops: const [0.0, 0.18, 0.48, 0.76, 1.0],
      ).createShader(sphereRect);
    canvas.drawCircle(center, radius, spherePaint);

    final innerDepthPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = radius * 0.11
      ..color = Colors.black.withOpacity(0.30)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * 0.045);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius * 0.90),
      math.pi * 0.03,
      math.pi * 0.88,
      false,
      innerDepthPaint,
    );

    final leftLiftPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = radius * 0.020
      ..color = Colors.white.withOpacity(0.16 + energy * 0.08)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * 0.010);
    canvas.drawArc(
      Rect.fromCircle(center: center.translate(-radius * 0.02, -radius * 0.02), radius: radius * 0.88),
      math.pi * 0.92,
      math.pi * 0.42,
      false,
      leftLiftPaint,
    );

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
      width: size.width * 0.44,
      height: size.height * 0.15,
    );
    final highlightPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          Colors.white.withOpacity(0.24),
          Colors.white.withOpacity(0.07),
          Colors.white.withOpacity(0.015),
        ],
      ).createShader(highlightRect);
    canvas.drawOval(highlightRect, highlightPaint);

    final glassCutPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = size.shortestSide * 0.010
      ..color = Colors.white.withOpacity(0.12)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.8);
    canvas.drawArc(
      Rect.fromCircle(
        center: center.translate(-radius * 0.07, -radius * 0.10),
        radius: radius * 0.78,
      ),
      math.pi * 1.05,
      math.pi * 0.34,
      false,
      glassCutPaint,
    );

    final lowerShade = Paint()
      ..color = Colors.black.withOpacity(0.40)
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.shortestSide * 0.072
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
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
