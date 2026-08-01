from pathlib import Path

path = Path('lib/services/gemini_service.dart')
text = path.read_text(encoding='utf-8')
old = "    return body.replaceAll(RegExp(r'\\s+'), ' ').trim().take(400);\n"
new = """    final compact = body.replaceAll(RegExp(r'\\s+'), ' ').trim();
    return compact.length > 400 ? compact.substring(0, 400) : compact;
"""
count = text.count(old)
if count != 1:
    raise RuntimeError(f'gemini error truncation: expected 1 match, found {count}')
path.write_text(text.replace(old, new, 1), encoding='utf-8')
print('v3.3 source preflight fix applied')
