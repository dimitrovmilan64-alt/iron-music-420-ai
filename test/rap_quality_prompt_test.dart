import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Rap Studio rejects clichés, filler and invented biography', () {
    final service = File('lib/services/gemini_service.dart').readAsStringSync();
    final studio = File('lib/pages/rap_studio_page_v2.dart').readAsStringSync();

    expect(service, contains('Римуваш смисъл, не само последната дума'));
    expect(service, contains('не измисляш биография'));
    expect(service, contains('мрак–прах'));
    expect(service, contains('Преди отговора правиш тиха редакторска проверка'));

    expect(studio, contains('Всеки ред трябва да движи историята или да носи удар'));
    expect(studio, contains('Без общи фрази, пълнеж'));
    expect(studio, contains('Не измисляй факти за живота на автора'));
    expect(studio, contains('римни поредици от 2–4 бара'));
  });
}
