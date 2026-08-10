from pathlib import Path
import re

COMMON = Path('lib/ui/common_widgets.dart')
CHAT = Path('lib/pages/chat_page.dart')
PUBSPEC = Path('pubspec.yaml')

common = COMMON.read_text(encoding='utf-8')
chat = CHAT.read_text(encoding='utf-8')
pubspec = PUBSPEC.read_text(encoding='utf-8')

new_core = r'''class CannabisCore extends StatelessWidget {
  final double progress;
  final double size;

  const CannabisCore({
    super.key,
    required this.progress,
    this.size = 300,
  });

  @override
  Widget build(BuildContext context) {
    final breathe = 0.985 + progress * 0.022;
    final glow = 0.16 + progress * 0.18;
    final tiltX = (progress - 0.5) * 0.045;
    final tiltY = (0.5 - progress) * 0.065;

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
          Transform.scale(
            scale: 0.94 + progress * 0.035,
            child: Container(
              width: size * 0.82,
              height: size * 0.82,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    ironGreen.withOpacity(0.10 + progress * 0.08),
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
                    color: ironGreen.withOpacity(glow),
                    blurRadius: 32 + progress * 22,
                    spreadRadius: 1 + progress * 3,
                  ),
                  BoxShadow(
                    color: Colors.black.withOpacity(0.72),
                    blurRadius: 24,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
            ),
          ),
          Transform.scale(
            scale: breathe,
            child: Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.0015)
                ..rotateX(tiltX)
                ..rotateY(tiltY),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  exactLeaf(),
                  Opacity(
                    opacity: 0.10 + progress * 0.18,
                    child: ShaderMask(
                      blendMode: BlendMode.srcATop,
                      shaderCallback: (bounds) => LinearGradient(
                        begin: Alignment(-1.0 + progress * 0.7, 1.0),
                        end: Alignment(0.8 + progress * 0.2, -1.0),
                        colors: const [
                          Colors.transparent,
                          Color(0xFFB9FFD0),
                          Color(0xFF45FF8B),
                          Colors.transparent,
                        ],
                        stops: const [0.05, 0.42, 0.56, 0.92],
                      ).createShader(bounds),
                      child: exactLeaf(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          IgnorePointer(
            child: Container(
              width: size * 0.76,
              height: size * 0.76,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withOpacity(0.035 + progress * 0.05),
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

COMMON.write_text(common, encoding='utf-8')
CHAT.write_text(chat, encoding='utf-8')
PUBSPEC.write_text(pubspec, encoding='utf-8')

print('Applied build 68 isolated UI patch: exact leaf, 3D breathing, pulse glow, no background duplicate leaves.')
