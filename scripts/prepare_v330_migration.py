from pathlib import Path

path = Path('scripts/apply_v330_provider_fallback.py')
text = path.read_text(encoding='utf-8')
old = "if count != 4:\n    raise RuntimeError(f'rap provider guards: expected 4 matches, found {count}')\n"
new = "if count != 3:\n    raise RuntimeError(f'rap provider guards: expected 3 standard matches, found {count}')\n"
count = text.count(old)
if count != 1:
    raise RuntimeError(f'prepare rap migration: expected 1 match, found {count}')
path.write_text(text.replace(old, new, 1), encoding='utf-8')
print('v3.3 migration prepared for three standard Rap Studio guards')
