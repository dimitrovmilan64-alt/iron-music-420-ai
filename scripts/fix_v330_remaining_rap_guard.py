from pathlib import Path

path = Path('lib/pages/rap_studio_page.dart')
text = path.read_text(encoding='utf-8')
old = """    if (apiKey.isEmpty) {
      _showMessage('Първо запази Gemini API ключа в раздел „Чат“.');
      return;
    }
"""
new = """    if (!widget.store.hasAnyAiProvider) {
      _showMessage('Първо добави Gemini или резервен AI доставчик в раздел „AI“.');
      return;
    }
"""
count = text.count(old)
if count != 1:
    raise RuntimeError(f'remaining rap provider guard: expected 1 match, found {count}')
path.write_text(text.replace(old, new, 1), encoding='utf-8')
print('remaining Rap Studio provider guard updated')
