from pathlib import Path
import re
import runpy

# Start from the already verified build 68 living/gyro core.
runpy.run_path('scripts/apply_build68_living_core.py', run_name='__main__')

COMMON = Path('lib/ui/common_widgets.dart')
CHAT = Path('lib/pages/chat_page.dart')
PUBSPEC = Path('pubspec.yaml')

common = COMMON.read_text(encoding='utf-8')
chat = CHAT.read_text(encoding='utf-8')
pubspec = PUBSPEC.read_text(encoding='utf-8')

modern_background = r'''class IronBackground extends StatelessWidget {
  final Widget child;
  final bool showHud;

  const IronBackground({
    super.key,
    required this.child,
    this.showHud = true,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0.0, -1.08),
          radius: 1.48,
          colors: [
            Color(0xFF07351A),
            Color(0xFF021109),
            Color(0xFF000603),
            Colors.black,
          ],
          stops: [0.0, 0.32, 0.70, 1.0],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (showHud)
            IgnorePointer(
              child: Opacity(
                opacity: 0.72,
                child: CustomPaint(painter: _HudBackgroundPainter()),
              ),
            ),
          IgnorePointer(
            child: Align(
              alignment: const Alignment(0, -0.72),
              child: Container(
                width: 330,
                height: 330,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      ironGreen.withOpacity(0.055),
                      ironGreenDeep.withOpacity(0.018),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.55, 1.0],
                  ),
                ),
              ),
            ),
          ),
          SafeArea(child: child),
        ],
      ),
    );
  }
}'''

pattern = re.compile(
    r'class IronBackground extends StatelessWidget \{.*?\n\}\n\nclass PageTitle',
    re.S,
)
common, count = pattern.subn(modern_background + '\n\nclass PageTitle', common, count=1)
if count != 1:
    raise SystemExit(f'IronBackground replacement count was {count}, expected 1')

modern_bottom_nav = r'''class IronBottomNavigation extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final List<IronNavItem> items;

  const IronBottomNavigation({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 0, 10, 8),
      decoration: BoxDecoration(
        color: const Color(0xFF020B06).withOpacity(0.985),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: ironGreen.withOpacity(0.18)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.64),
            blurRadius: 24,
            offset: const Offset(0, -2),
          ),
          BoxShadow(
            color: ironGreen.withOpacity(0.055),
            blurRadius: 22,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 70,
            child: Row(
              children: List.generate(items.length, (index) {
                final item = items[index];
                final selected = index == selectedIndex;
                return Expanded(
                  child: InkWell(
                    onTap: () => onSelected(index),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOutCubic,
                          width: selected ? 58 : 44,
                          height: 36,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(18),
                            gradient: selected
                                ? LinearGradient(
                                    colors: [
                                      ironGreen.withOpacity(0.20),
                                      ironGreenDeep.withOpacity(0.08),
                                    ],
                                  )
                                : null,
                            border: Border.all(
                              color: selected
                                  ? ironGreen.withOpacity(0.34)
                                  : Colors.transparent,
                            ),
                            boxShadow: selected
                                ? [
                                    BoxShadow(
                                      color: ironGreen.withOpacity(0.14),
                                      blurRadius: 14,
                                    ),
                                  ]
                                : null,
                          ),
                          child: Icon(
                            selected ? item.selectedIcon : item.icon,
                            color: selected ? ironGreenSoft : Colors.white38,
                            size: selected ? 23 : 21,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          item.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: selected ? ironGreen : Colors.white38,
                            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                            fontSize: 9.5,
                            letterSpacing: selected ? 0.15 : 0,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}'''

pattern = re.compile(
    r'class IronBottomNavigation extends StatelessWidget \{.*?\n\}\n\nclass IronNavItem',
    re.S,
)
common, count = pattern.subn(modern_bottom_nav + '\n\nclass IronNavItem', common, count=1)
if count != 1:
    raise SystemExit(f'IronBottomNavigation replacement count was {count}, expected 1')

modern_chat_build = r'''  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final keyboardOpen = media.viewInsets.bottom > 0;
    final compactHeight = media.size.height < 720;
    final coreSize = compactHeight ? 146.0 : 184.0;

    return IronBackground(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 12, 0),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'IRON MUSIC',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 3.0,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const Text(
                            '420',
                            style: TextStyle(
                              color: ironGreenSoft,
                              fontSize: 29,
                              height: 0.96,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.2,
                              shadows: [Shadow(color: ironGreen, blurRadius: 15)],
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'AI',
                            style: TextStyle(
                              color: ironGreen.withOpacity(0.92),
                              fontSize: 24,
                              height: 1.0,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.0,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'ТВОЯТ AI РАП ПРОДЮЦЕНТ',
                        style: TextStyle(
                          color: ironGreen.withOpacity(0.72),
                          fontSize: 8.8,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.7,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    color: const Color(0xFF06140B).withOpacity(0.92),
                    border: Border.all(color: ironGreen.withOpacity(0.20)),
                    boxShadow: [
                      BoxShadow(
                        color: ironGreen.withOpacity(0.06),
                        blurRadius: 14,
                      ),
                    ],
                  ),
                  child: PopupMenuButton<String>(
                    tooltip: 'Настройки',
                    icon: const Icon(Icons.tune_rounded, color: ironGreen, size: 21),
                    onSelected: (value) {
                      if (value == 'api') {
                        _openApiKeySheet();
                      } else if (value == 'voice') {
                        _openVoiceSettings();
                      } else if (value == 'history') {
                        _clearHistory();
                      } else if (value == 'tools') {
                        widget.onOpenTools?.call();
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(value: 'api', child: Text('AI доставчици')),
                      const PopupMenuItem(value: 'voice', child: Text('Настройки на гласа')),
                      if (widget.onOpenTools != null)
                        const PopupMenuItem(value: 'tools', child: Text('Инструменти')),
                      const PopupMenuItem(value: 'history', child: Text('Изчисти историята')),
                    ],
                  ),
                ),
              ],
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            child: keyboardOpen
                ? const SizedBox(height: 4)
                : Padding(
                    padding: EdgeInsets.fromLTRB(
                      10,
                      compactHeight ? 2 : 5,
                      10,
                      4,
                    ),
                    child: _buildAssistantCore(coreSize),
                  ),
          ),
          if (!keyboardOpen)
            GestureDetector(
              onTap: _openApiKeySheet,
              child: Container(
                margin: const EdgeInsets.fromLTRB(14, 0, 14, 7),
                padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFF07180D).withOpacity(0.97),
                      const Color(0xFF020A05).withOpacity(0.98),
                    ],
                  ),
                  border: Border.all(color: ironGreen.withOpacity(0.22)),
                  boxShadow: [
                    BoxShadow(
                      color: ironGreen.withOpacity(0.055),
                      blurRadius: 18,
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 31,
                      height: 31,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: ironGreen.withOpacity(0.10),
                        border: Border.all(color: ironGreen.withOpacity(0.34)),
                      ),
                      child: Icon(
                        widget.store.hasAnyAiProvider
                            ? Icons.verified_user_rounded
                            : Icons.key_rounded,
                        size: 17,
                        color: ironGreen,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.store.hasAnyAiProvider
                                ? 'AI СИСТЕМАТА Е ГОТОВА'
                                : 'ДОБАВИ AI КЛЮЧ',
                            style: const TextStyle(
                              color: ironGreen,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.7,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _ironActive
                                ? 'Hey Iron • Български глас • Онлайн'
                                : 'Чат • Български глас',
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 10.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: widget.store.hasAnyAiProvider
                            ? ironGreenSoft
                            : Colors.orangeAccent,
                        boxShadow: widget.store.hasAnyAiProvider
                            ? [
                                BoxShadow(
                                  color: ironGreen.withOpacity(0.5),
                                  blurRadius: 8,
                                ),
                              ]
                            : null,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(14, 3, 14, 7),
              itemCount: _messages.length + (_isLoading ? 1 : 0),
              itemBuilder: (context, index) {
                if (_isLoading && index == _messages.length) {
                  return Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.fromLTRB(0, 5, 0, 12),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        color: const Color(0xFF06140B).withOpacity(0.90),
                        border: Border.all(color: ironGreen.withOpacity(0.14)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 15,
                            height: 15,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.8,
                              color: ironGreen,
                            ),
                          ),
                          SizedBox(width: 9),
                          Text('Iron мисли...', style: TextStyle(color: ironGreen)),
                        ],
                      ),
                    ),
                  );
                }
                final message = _messages[index];
                return _ChatBubble(
                  message: message,
                  onSendToStudio: !message.isUser && !message.isLocalNotice
                      ? () => _sendTextToStudio(message.text)
                      : null,
                );
              },
            ),
          ),
          Container(
            margin: const EdgeInsets.fromLTRB(11, 4, 11, 9),
            padding: const EdgeInsets.fromLTRB(14, 7, 6, 7),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(25),
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF07180D).withOpacity(0.98),
                  const Color(0xFF010804).withOpacity(0.99),
                ],
              ),
              border: Border.all(color: ironGreen.withOpacity(0.25)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.50),
                  blurRadius: 18,
                  offset: const Offset(0, 7),
                ),
                BoxShadow(
                  color: ironGreen.withOpacity(0.06),
                  blurRadius: 18,
                ),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    minLines: 1,
                    maxLines: 4,
                    textCapitalization: TextCapitalization.sentences,
                    style: const TextStyle(color: Colors.white, height: 1.3),
                    decoration: InputDecoration.collapsed(
                      hintText: _isListening
                          ? 'Слушам на български...'
                          : 'Говори или напиши на Iron...',
                      hintStyle: const TextStyle(color: Colors.white38),
                    ),
                    onSubmitted: (_) {
                      if (!_isLoading) _sendMessage();
                    },
                  ),
                ),
                IconButton(
                  tooltip: 'Микрофон',
                  onPressed: _isLoading ? null : _toggleListening,
                  icon: Icon(
                    _isListening ? Icons.stop_circle_rounded : Icons.mic_none_rounded,
                    color: _isListening ? Colors.redAccent : ironGreenSoft,
                  ),
                ),
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [ironGreenSoft, ironGreen],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: ironGreen.withOpacity(0.24),
                        blurRadius: 14,
                      ),
                    ],
                  ),
                  child: IconButton(
                    tooltip: 'Изпрати',
                    onPressed: _isLoading ? null : _sendMessage,
                    icon: const Icon(Icons.arrow_upward_rounded, color: Colors.black),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }'''

pattern = re.compile(
    r'  @override\n  Widget build\(BuildContext context\) \{\n    final media = MediaQuery\.of\(context\);.*?\n  \}\n\n\}\n\nclass _ChatBubble',
    re.S,
)
chat, count = pattern.subn(modern_chat_build + '\n\n}\n\nclass _ChatBubble', chat, count=1)
if count != 1:
    raise SystemExit(f'Chat build replacement count was {count}, expected 1')

modern_bubble = r'''class _ChatBubble extends StatelessWidget {
  final ChatMessage message;
  final VoidCallback? onSendToStudio;

  const _ChatBubble({
    required this.message,
    this.onSendToStudio,
  });

  @override
  Widget build(BuildContext context) {
    final alignment = message.isUser ? Alignment.centerRight : Alignment.centerLeft;
    final borderColor = message.isLocalNotice
        ? Colors.orangeAccent.withOpacity(0.42)
        : message.isUser
            ? ironGreen.withOpacity(0.38)
            : Colors.white.withOpacity(0.075);

    return Align(
      alignment: alignment,
      child: Container(
        margin: const EdgeInsets.only(bottom: 9),
        padding: const EdgeInsets.fromLTRB(13, 10, 12, 11),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.88,
        ),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: message.isUser
                ? [
                    ironGreen.withOpacity(0.15),
                    const Color(0xFF04120A).withOpacity(0.97),
                  ]
                : message.isLocalNotice
                    ? [
                        Colors.orange.withOpacity(0.10),
                        const Color(0xFF120D03).withOpacity(0.94),
                      ]
                    : [
                        const Color(0xFF07150C).withOpacity(0.94),
                        const Color(0xFF020805).withOpacity(0.97),
                      ],
          ),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(19),
            topRight: const Radius.circular(19),
            bottomLeft: Radius.circular(message.isUser ? 19 : 6),
            bottomRight: Radius.circular(message.isUser ? 6 : 19),
          ),
          border: Border.all(color: borderColor),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.22),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
            if (message.isUser)
              BoxShadow(
                color: ironGreen.withOpacity(0.045),
                blurRadius: 16,
              ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: message.isUser
                        ? ironGreenSoft
                        : message.isLocalNotice
                            ? Colors.orangeAccent
                            : ironGreen,
                  ),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    message.sender.toUpperCase(),
                    style: TextStyle(
                      color: message.isUser ? ironGreenSoft : Colors.white54,
                      fontWeight: FontWeight.w800,
                      fontSize: 9.5,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
                if (onSendToStudio != null) ...[
                  InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: onSendToStudio,
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(
                        Icons.mic_external_on_rounded,
                        size: 16,
                        color: ironGreen,
                      ),
                    ),
                  ),
                  const SizedBox(width: 3),
                ],
                InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () async {
                    await Clipboard.setData(ClipboardData(text: message.text));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Съобщението е копирано.')),
                      );
                    }
                  },
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.copy_rounded, size: 14, color: Colors.white38),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            SelectableText(
              cleanMarkdownForDisplay(message.text),
              style: const TextStyle(
                color: Colors.white,
                height: 1.42,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}'''

pattern = re.compile(r'class _ChatBubble extends StatelessWidget \{.*\Z', re.S)
chat, count = pattern.subn(modern_bubble, chat, count=1)
if count != 1:
    raise SystemExit(f'Chat bubble replacement count was {count}, expected 1')

old_version = 'version: 3.4.0+68'
new_version = 'version: 3.4.0+70'
if old_version not in pubspec:
    raise SystemExit('Expected build 68 version after gyro patch was not found')
pubspec = pubspec.replace(old_version, new_version, 1)

COMMON.write_text(common, encoding='utf-8')
CHAT.write_text(chat, encoding='utf-8')
PUBSPEC.write_text(pubspec, encoding='utf-8')

print('Applied build 70 modern UI over verified gyro core: premium header, status glass, modern chat bubbles/composer and pill navigation.')
