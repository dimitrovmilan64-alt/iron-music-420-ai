from pathlib import Path
import re

COMMON = Path('lib/ui/common_widgets.dart')
CHAT = Path('lib/pages/chat_page.dart')
PUBSPEC = Path('pubspec.yaml')

common = COMMON.read_text(encoding='utf-8')
chat = CHAT.read_text(encoding='utf-8')
pubspec = PUBSPEC.read_text(encoding='utf-8')

old_imports = "import 'dart:math' as math;\n\nimport 'package:flutter/material.dart';"
new_imports = "import 'dart:async';\nimport 'dart:math' as math;\n\nimport 'package:flutter/material.dart';\nimport 'package:sensors_plus/sensors_plus.dart';"
if old_imports not in common:
    raise SystemExit('Expected common_widgets imports were not found')
common = common.replace(old_imports, new_imports, 1)

new_core = r'''class CannabisCore extends StatefulWidget {
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
    final breathe = 0.985 + progress * 0.022;
    final motion = ((_tiltX.abs() + _tiltY.abs()) / 0.33)
        .clamp(0.0, 1.0)
        .toDouble();
    final glow = 0.16 + progress * 0.18 + motion * 0.08;
    final idleTiltX = (progress - 0.5) * 0.012;
    final idleTiltY = (0.5 - progress) * 0.018;
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
          width: size,
          height: size,
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
            offset: depthOffset * 0.42,
            child: Transform.scale(
              scale: 0.94 + progress * 0.035 + motion * 0.012,
              child: Container(
                width: size * 0.82,
                height: size * 0.82,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    center: Alignment(lightX * 0.34, lightY * 0.34),
                    colors: [
                      ironGreen.withOpacity(0.10 + progress * 0.08 + motion * 0.04),
                      ironGreenDeep.withOpacity(0.055),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.58, 1.0],
                  ),
                  border: Border.all(
                    color: ironGreen.withOpacity(0.15 + progress * 0.11),
                    width: 1.2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: ironGreen.withOpacity(
                        glow.clamp(0.0, 0.48).toDouble(),
                      ),
                      blurRadius: 32 + progress * 22 + motion * 12,
                      spreadRadius: 1 + progress * 3 + motion * 1.5,
                    ),
                    BoxShadow(
                      color: Colors.black.withOpacity(0.72),
                      blurRadius: 24 + motion * 7,
                      offset: Offset(
                        -depthOffset.dx * 0.22,
                        12 - depthOffset.dy * 0.22,
                      ),
                    ),
                  ],
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
                    exactLeaf(),
                    Opacity(
                      opacity: (0.10 + progress * 0.18 + motion * 0.16)
                          .clamp(0.0, 0.42)
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
                      0.035 + progress * 0.05 + motion * 0.025,
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
}'''

pattern = re.compile(
    r'class CannabisCore extends StatelessWidget \{.*?\n\}\n\nclass IronBottomNavigation',
    re.S,
)
common, count = pattern.subn(new_core + '\n\nclass IronBottomNavigation', common, count=1)
if count != 1:
    raise SystemExit(f'CannabisCore replacement count was {count}, expected 1')

watermark_block = '''    final watermarkPaint = Paint()\n      ..color = ironGreen.withOpacity(0.035)\n      ..style = PaintingStyle.stroke\n      ..strokeWidth = 1;\n    _drawTinyLeaf(\n      canvas,\n      Offset(size.width * 0.09, size.height * 0.58),\n      18,\n      watermarkPaint,\n    );\n    _drawTinyLeaf(\n      canvas,\n      Offset(size.width * 0.91, size.height * 0.79),\n      22,\n      watermarkPaint,\n    );\n'''
if watermark_block not in common:
    raise SystemExit('Expected two background leaf watermarks were not found')
common = common.replace(watermark_block, '', 1)

old_size = 'final coreSize = compactHeight ? 126.0 : 156.0;'
new_size = 'final coreSize = compactHeight ? 152.0 : 188.0;'
if old_size not in chat:
    raise SystemExit('Expected stable core size line was not found')
chat = chat.replace(old_size, new_size, 1)

old_version = 'version: 3.4.0+67'
new_version = 'version: 3.4.0+68'
if old_version not in pubspec:
    raise SystemExit('Expected stable build 67 version was not found')
pubspec = pubspec.replace(old_version, new_version, 1)

old_dependency = '  share_plus: ^10.1.4\n'
new_dependency = '  share_plus: ^10.1.4\n  sensors_plus: ^6.1.2\n'
if old_dependency not in pubspec:
    raise SystemExit('Expected share_plus dependency line was not found')
pubspec = pubspec.replace(old_dependency, new_dependency, 1)

COMMON.write_text(common, encoding='utf-8')
CHAT.write_text(chat, encoding='utf-8')
PUBSPEC.write_text(pubspec, encoding='utf-8')

print('Applied build 68 isolated UI patch: exact leaf + gyroscope 3D parallax, dynamic light/depth, pulse glow, no background duplicate leaves.')
