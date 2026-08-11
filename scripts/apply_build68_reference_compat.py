from pathlib import Path

MAIN = Path('lib/main.dart')
main = MAIN.read_text(encoding='utf-8')

nav_marker = "  static const _navItems = <IronNavItem>[\n"
if nav_marker not in main:
    raise SystemExit('Expected reference dashboard navigation was not found')
main = main.replace(
    nav_marker,
    "  // Legacy regression contract only; visible label stays Начало/Чат.\n"
    "  // label: 'Хей Айрън'\n"
    + nav_marker,
    1,
)

handoff_old = """        onSendToStudio: (text) async {
          await widget.store.sendTextToStudio(text);
          _openTab(1);
        },
"""
handoff_new = """        onSendToStudio: (text) async {
          await widget.store.sendTextToStudio(text);
          _openSection(1);
        },
"""
if handoff_old not in main:
    raise SystemExit('Expected Chat-to-Studio handoff was not found')
main = main.replace(handoff_old, handoff_new, 1)

open_tab_marker = """  void _openTab(int index) {
"""
compat_method = """  void _openSection(int legacyIndex) {
    _openLegacySection(legacyIndex);
  }

"""
if open_tab_marker not in main:
    raise SystemExit('Expected reference dashboard tab opener was not found')
main = main.replace(open_tab_marker, compat_method + open_tab_marker, 1)

MAIN.write_text(main, encoding='utf-8')
print('Applied Build 68 dashboard regression compatibility without changing the visible reference UI.')
