from pathlib import Path

path = Path('lib/ui/common_widgets.dart')
text = path.read_text(encoding='utf-8')
start = text.index('class CannabisCore extends StatelessWidget {')
end = text.index('class IronBottomNavigation extends StatelessWidget {')

replacement = r'''class CannabisCore extends StatelessWidget {
  final double progress;
  final double size;

  const CannabisCore({
    super.key,
    required this.progress,
    this.size = 300,
  });

  @override
  Widget build(BuildContext context) {
    final pulse = 0.96 + progress * 0.045;
    final orbit = (progress - 0.5) * math.pi * 0.20;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          Transform.translate(
            offset: Offset(0, size * 0.27),
            child: Container(
              width: size * 0.72,
              height: size * 0.16,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.all(Radius.elliptical(size, size * 0.25)),
                gradient: RadialGradient(
                  colors: [
                    ironGreen.withOpacity(0.34 + progress * 0.22),
                    ironGreen.withOpacity(0.08),
                    Colors.transparent,
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: ironGreen.withOpacity(0.20 + progress * 0.20),
                    blurRadius: 26 + progress * 18,
                    spreadRadius: 2,
                  ),
                ],
              ),
            ),
          ),
          Transform.scale(
            scale: pulse,
            child: Container(
              width: size * 0.94,
              height: size * 0.94,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFF082514).withOpacity(0.30),
                    const Color(0xFF031108).withOpacity(0.72),
                    Colors.black.withOpacity(0.92),
                  ],
                  stops: const [0.0, 0.62, 1.0],
                ),
                border: Border.all(
                  color: ironGreen.withOpacity(0.28 + progress * 0.18),
                  width: 1.1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: ironGreen.withOpacity(0.18 + progress * 0.20),
                    blurRadius: 34 + progress * 22,
                    spreadRadius: 3,
                  ),
                  const BoxShadow(
                    color: Colors.black87,
                    blurRadius: 18,
                    offset: Offset(0, 10),
                  ),
                ],
              ),
            ),
          ),
          Transform.rotate(
            angle: orbit,
            child: CustomPaint(
              size: Size.square(size),
              painter: _ReactorShellPainter(
                progress: progress,
                reverse: false,
              ),
            ),
          ),
          Transform.rotate(
            angle: -orbit * 0.72,
            child: CustomPaint(
              size: Size.square(size * 0.88),
              painter: _ReactorShellPainter(
                progress: progress,
                reverse: true,
              ),
            ),
          ),
          Transform.scale(
            scale: 0.74 + progress * 0.018,
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    ironGreen.withOpacity(0.15 + progress * 0.16),
                    const Color(0xFF021008).withOpacity(0.76),
                    Colors.black.withOpacity(0.14),
                  ],
                  stops: const [0.0, 0.64, 1.0],
                ),
                border: Border.all(
                  color: ironGreenSoft.withOpacity(0.20 + progress * 0.18),
                ),
              ),
            ),
          ),
          Transform.scale(
            scale: 0.66 + progress * 0.025,
            child: Image.asset(
              'assets/images/hud_core_exact.png',
              width: size,
              height: size,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
              errorBuilder: (context, error, stackTrace) => CustomPaint(
                size: Size.square(size),
                painter: _CannabisLeafPainter(glow: progress),
              ),
            ),
          ),
          IgnorePointer(
            child: Container(
              width: size * 0.55,
              height: size * 0.55,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withOpacity(0.07 + progress * 0.08),
                ),
                boxShadow: [
                  BoxShadow(
                    color: ironGreenSoft.withOpacity(0.08 + progress * 0.16),
                    blurRadius: 20,
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            bottom: size * 0.03,
            child: Container(
              width: size * 0.62,
              height: size * 0.055,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                gradient: LinearGradient(
                  colors: [
                    Colors.transparent,
                    ironGreen.withOpacity(0.34),
                    ironGreenSoft.withOpacity(0.95),
                    ironGreen.withOpacity(0.34),
                    Colors.transparent,
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: ironGreen.withOpacity(0.28 + progress * 0.24),
                    blurRadius: 16,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReactorShellPainter extends CustomPainter {
  final double progress;
  final bool reverse;

  const _ReactorShellPainter({
    required this.progress,
    required this.reverse,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    final direction = reverse ? -1.0 : 1.0;

    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..color = ironGreen.withOpacity(0.16 + progress * 0.20);

    for (final factor in [0.96, 0.88, 0.78]) {
      canvas.drawCircle(center, radius * factor, ringPaint);
    }

    final metalPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(2.0, size.shortestSide * 0.024)
      ..strokeCap = StrokeCap.butt
      ..shader = SweepGradient(
        transform: GradientRotation(direction * progress * math.pi * 0.42),
        colors: [
          const Color(0xFF0B2114),
          const Color(0xFF4A6353),
          ironGreen.withOpacity(0.88),
          const Color(0xFF15261B),
          ironGreenSoft.withOpacity(0.72),
          const Color(0xFF07120B),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: radius));

    const segments = 12;
    for (var i = 0; i < segments; i++) {
      final start = i * math.pi * 2 / segments + direction * progress * 0.18;
      final sweep = math.pi * 2 / segments * 0.58;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius * 0.91),
        start,
        sweep,
        false,
        metalPaint,
      );
    }

    final energyPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.4, size.shortestSide * 0.010)
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        transform: GradientRotation(-direction * progress * math.pi * 0.70),
        colors: [
          Colors.transparent,
          ironGreen.withOpacity(0.30),
          ironGreenSoft,
          Colors.white.withOpacity(0.82),
          ironGreenSoft,
          Colors.transparent,
        ],
        stops: const [0.0, 0.20, 0.38, 0.47, 0.58, 0.78],
      ).createShader(Rect.fromCircle(center: center, radius: radius));

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius * 0.82),
      direction * progress * math.pi,
      math.pi * 1.30,
      false,
      energyPaint,
    );

    final tickPaint = Paint()
      ..strokeWidth = 1.0
      ..color = ironGreenSoft.withOpacity(0.24 + progress * 0.26);
    for (var i = 0; i < 48; i++) {
      final angle = i * math.pi * 2 / 48 + direction * progress * 0.14;
      final strong = i % 6 == 0;
      final inner = radius * (strong ? 0.70 : 0.74);
      final outer = radius * (strong ? 0.78 : 0.77);
      canvas.drawLine(
        center + Offset(math.cos(angle) * inner, math.sin(angle) * inner),
        center + Offset(math.cos(angle) * outer, math.sin(angle) * outer),
        tickPaint,
      );
    }

    final nodePaint = Paint()
      ..color = ironGreenSoft.withOpacity(0.55 + progress * 0.38)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    for (final i in [1, 7, 13, 19, 31, 41]) {
      final angle = i * math.pi * 2 / 48 - direction * progress * 0.20;
      final p = center + Offset(
        math.cos(angle) * radius * 0.84,
        math.sin(angle) * radius * 0.84,
      );
      canvas.drawCircle(p, strongNodeRadius(size), nodePaint);
    }
  }

  double strongNodeRadius(Size size) =>
      math.max(1.4, size.shortestSide * (0.008 + progress * 0.002));

  @override
  bool shouldRepaint(covariant _ReactorShellPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.reverse != reverse;
}

'''

text = text[:start] + replacement + text[end:]
path.write_text(text, encoding='utf-8')
print('Applied 3D cannabis reactor core UI')
