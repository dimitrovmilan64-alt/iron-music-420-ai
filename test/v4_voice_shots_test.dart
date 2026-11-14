import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ironmusic420ai/services/iron_tts.dart';
import 'package:ironmusic420ai/ui/common_widgets.dart';

Future<ByteData> _fileBytes(String path) async {
  final bytes = File(path).readAsBytesSync();
  return ByteData.view(bytes.buffer);
}

Future<void> _loadInter() async {
  final inter = await rootBundle.load('assets/fonts/InterVariable.ttf');
  await (FontLoader('Inter')..addFont(Future.value(inter))).load();

  const iconPath =
      '/home/box/sdk/flutter-3.47.9/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf';
  if (File(iconPath).existsSync()) {
    final icons = await _fileBytes(iconPath);
    await (FontLoader('MaterialIcons')..addFont(Future.value(icons))).load();
  }
}

Future<void> _saveShot(WidgetTester tester, String name) async {
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('iron-shot')),
    );
    final image = await boundary.toImage(pixelRatio: 2.6);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final dir = Directory('/workspace/iron-shots/v4')
      ..createSync(recursive: true);
    File('${dir.path}/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

class _VoiceShotPanel extends StatelessWidget {
  const _VoiceShotPanel({required this.voices});

  final List<IronVoiceOption> voices;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0F0C),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
            const Text(
              'Глас',
              style: TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'По подразбиране се ползва естествен глас на Gemini на български. Английският се включва автоматично при английски текст. Groq е допълнителна опция само за английски.',
              style: TextStyle(color: Colors.white70, height: 1.35),
            ),
            const SizedBox(height: 16),
            IronCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Скорост',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w700)),
                  Slider(value: 0.50, min: 0.3, max: 0.7, onChanged: (_) {}),
                  const SizedBox(height: 8),
                  const Text('Височина',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w700)),
                  Slider(value: 1.00, min: 0.8, max: 1.3, onChanged: (_) {}),
                ],
              ),
            ),
            const SizedBox(height: 12),
            IronCard(
              child: Column(
                children: [
                  for (var i = 0; i < voices.length; i++) ...[
                    if (i > 0)
                      const Divider(height: 1, color: ironOutlineMuted),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      selected: i == 0,
                      title: Text(
                        voices[i].title,
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight:
                              i == 0 ? FontWeight.w800 : FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        '${voices[i].locale} · ${voices[i].badge}',
                        style: const TextStyle(
                            color: Colors.white60, fontSize: 12),
                      ),
                    ),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: null,
                        child: Text(
                          'Чуй пробен глас',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('write v4 voice settings screenshots', (tester) async {
    await _loadInter();
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final voices = IronTts.cloudVoices(hasGemini: true, hasGroq: true);

    await tester.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('iron-shot'),
        child: MaterialApp(
          theme: ironTheme(),
          home: _VoiceShotPanel(voices: voices.take(6).toList()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Sulafat'), findsWidgets);
    expect(find.text('Чуй пробен глас'), findsWidgets);
    await _saveShot(tester, 'after-settings-voice');

    await tester.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('iron-shot'),
        child: MaterialApp(
          theme: ironTheme(),
          home: _VoiceShotPanel(voices: voices.skip(6).toList()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Autumn'), findsWidgets);
    await _saveShot(tester, 'after-settings-voice-en');
  });
}
