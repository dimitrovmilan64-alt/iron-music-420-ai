from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected exactly 1 match, found {count}")
    return text.replace(old, new, 1)


chat_path = Path("lib/pages/chat_page.dart")
text = chat_path.read_text(encoding="utf-8")

text = replace_once(
    text,
    """  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text)),
    );
  }
""",
    """  void _showMessage(String text) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(text),
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.fromLTRB(
            16,
            8,
            16,
            96 + MediaQuery.of(context).viewInsets.bottom,
          ),
          duration: const Duration(seconds: 2),
        ),
      );
  }
""",
    "floating snackbar",
)

text = replace_once(
    text,
    """    if (!_showApiBox) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          children: [
            Expanded(
              child: IronButton(
                text: 'API ключът е запазен',
                icon: Icons.lock,
                secondary: true,
                onPressed: () => setState(() => _showApiBox = true),
              ),
            ),
          ],
        ),
      );
    }
""",
    """    if (!_showApiBox) {
      return const SizedBox.shrink();
    }
""",
    "remove saved API banner",
)

text = replace_once(
    text,
    """  Widget _coreControl({
    required IconData icon,
    required String tooltip,
    required bool active,
    required VoidCallback? onPressed,
  }) {
""",
    """  Widget _coreControl({
    required IconData icon,
    required String tooltip,
    required bool active,
    required VoidCallback? onPressed,
    required double size,
  }) {
""",
    "responsive control signature",
)

text = replace_once(text, "          width: 44,\n          height: 44,", "          width: size,\n          height: size,", "responsive control size")
text = replace_once(text, "            size: 21,", "            size: size * 0.48,", "responsive control icon")

text = replace_once(
    text,
    """  Widget build(BuildContext context) {
    final showLargeCore = _messages.length <= 2;

    return IronBackground(
""",
    """  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final usableHeight = media.size.height -
        media.padding.vertical -
        media.viewInsets.bottom;
    final keyboardOpen = media.viewInsets.bottom > 0;
    final compactHeight = usableHeight < 680;
    final showLargeCore =
        _messages.length <= 2 && !keyboardOpen && !compactHeight;
    final coreSize = keyboardOpen
        ? 88.0
        : showLargeCore
            ? 164.0
            : compactHeight
                ? 108.0
                : 122.0;
    final controlSize = compactHeight || keyboardOpen ? 40.0 : 44.0;

    return IronBackground(
""",
    "responsive measurements",
)

text = replace_once(
    text,
    """          AnimatedContainer(
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOut,
            height: showLargeCore ? 260 : 190,
            child: AnimatedBuilder(
""",
    """          AnimatedSize(
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOut,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                12,
                keyboardOpen ? 2 : (showLargeCore ? 8 : 4),
                12,
                keyboardOpen ? 4 : 8,
              ),
              child: AnimatedBuilder(
""",
    "remove fixed core height",
)

text = replace_once(
    text,
    """                return Column(
                  mainAxisAlignment: MainAxisAlignment.center,
""",
    """                return Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
""",
    "core natural height",
)

text = replace_once(
    text,
    "                          size: showLargeCore ? 176 : 120,",
    "                          size: coreSize,",
    "responsive leaf size",
)

for marker in (
    "                          onPressed: _toggleConversationMode,",
    "                          onPressed: _ironBusy ? null : _toggleIron,",
    "                          onPressed: _toggleVoiceReplies,",
):
    text = replace_once(
        text,
        marker,
        marker + "\n                          size: controlSize,",
        f"control size after {marker.strip()}",
    )

text = replace_once(
    text,
    """              },
            ),
          ),
          _buildApiSection(),
""",
    """              },
            ),
          ),
        ),
          _buildApiSection(),
""",
    "close responsive core padding",
)

text = replace_once(
    text,
    """                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Съобщението е копирано.')),
                      );
""",
    """                      final messenger = ScaffoldMessenger.of(context);
                      messenger
                        ..hideCurrentSnackBar()
                        ..showSnackBar(
                          SnackBar(
                            content: const Text('Съобщението е копирано.'),
                            behavior: SnackBarBehavior.floating,
                            margin: EdgeInsets.fromLTRB(
                              16,
                              8,
                              16,
                              96 + MediaQuery.of(context).viewInsets.bottom,
                            ),
                            duration: const Duration(seconds: 2),
                          ),
                        );
""",
    "copy snackbar placement",
)

# Basic safety checks for the reported regression.
if "height: showLargeCore ? 260 : 190" in text:
    raise RuntimeError("fixed-height core still present")
if "BOTTOM OVERFLOWED" in text:
    raise RuntimeError("debug overflow marker unexpectedly present in source")
if "text: 'API ключът е запазен'" in text:
    raise RuntimeError("saved API banner still present")

chat_path.write_text(text, encoding="utf-8")

pubspec_path = Path("pubspec.yaml")
pubspec = pubspec_path.read_text(encoding="utf-8")
pubspec = replace_once(pubspec, "version: 3.1.1+35", "version: 3.1.2+36", "version bump")
pubspec_path.write_text(pubspec, encoding="utf-8")

changelog = Path("CHANGELOG_V312_RESPONSIVE_UI.txt")
changelog.write_text(
    """Iron Music 420 AI v3.1.2\n\n"
    "- Премахната е фиксираната височина на централния Iron кръг.\n"
    "- Листото и трите контроли се мащабират според реалната височина на екрана.\n"
    "- При отворена клавиатура централният кръг се свива автоматично.\n"
    "- Премахната е постоянната карта „API ключът е запазен“.\n"
    "- SnackBar съобщенията се показват над полето за писане.\n"
    "- Версия: 3.1.2+36.\n"
    """,
    encoding="utf-8",
)

print("v3.1.2 responsive UI fix applied successfully")
