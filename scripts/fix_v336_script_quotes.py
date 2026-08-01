from pathlib import Path

path = Path('scripts/apply_v336_chat_music_actions.py')
text = path.read_text(encoding='utf-8')
start = "    '''  String? _detectMusicCommand(String value) {\n"
end = "  Future<void> _syncNativeAiSettings() {\n''',\n)"
if start not in text:
    raise SystemExit('v3.3.6 insertion start marker not found')
if end not in text:
    raise SystemExit('v3.3.6 insertion end marker not found')
text = text.replace(
    start,
    '    """  String? _detectMusicCommand(String value) {\n',
    1,
)
text = text.replace(
    end,
    '  Future<void> _syncNativeAiSettings() {\n""",\n)',
    1,
)
path.write_text(text, encoding='utf-8')
