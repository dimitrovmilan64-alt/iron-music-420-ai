from pathlib import Path

path = Path('scripts/apply_build69_rap_studio.py')
text = path.read_text(encoding='utf-8')
old = 'pattern.subn(replacement, text, count=1)'
new = 'pattern.subn(lambda _: replacement, text, count=1)'
count = text.count(old)
if count != 2:
    raise RuntimeError(f'build69 replacement safety: expected 2 subn calls, found {count}')
path.write_text(text.replace(old, new), encoding='utf-8')
print('Build 69 patch runner made replacement strings literal-safe.')
