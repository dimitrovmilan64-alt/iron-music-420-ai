from pathlib import Path

MAIN = Path('lib/main.dart')
main = MAIN.read_text(encoding='utf-8')

marker = 'class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver {'
start = main.find(marker)
if start == -1:
    raise SystemExit('Expected MainScreen state marker was not found')

replacement = r'''class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  final AutomationService _automation = AutomationService();
  int _currentIndex = 0;
  late final List<Widget> _pages;

  static const _navItems = <IronNavItem>[
    IronNavItem(
      icon: Icons.home_outlined,
      selectedIcon: Icons.home_rounded,
      label: 'Начало',
    ),
    IronNavItem(
      icon: Icons.mic_external_on_outlined,
      selectedIcon: Icons.mic_external_on,
      label: 'Студио',
    ),
    IronNavItem(
      icon: Icons.library_music_outlined,
      selectedIcon: Icons.library_music,
      label: 'Песни',
    ),
    IronNavItem(
      icon: Icons.chat_bubble_outline_rounded,
      selectedIcon: Icons.chat_bubble_rounded,
      label: 'Чат',
    ),
    IronNavItem(
      icon: Icons.settings_outlined,
      selectedIcon: Icons.settings_rounded,
      label: 'Настр.',
    ),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _automation.setPendingRequestListener(_openPendingSection);
    _pages = [
      _IronHomeDashboard(
        store: widget.store,
        onOpenChat: () => _openTab(3),
        onOpenStudio: () => _openTab(1),
        onOpenSongs: () => _openTab(2),
        onOpenVoice: () => _openTab(3),
        onOpenTools: () => _openTab(4),
      ),
      RapStudioPage(store: widget.store),
      SongsPage(store: widget.store, onOpenStudio: () => _openTab(1)),
      ChatPage(
        store: widget.store,
        onOpenTools: () => _openTab(4),
        onSendToStudio: (text) async {
          await widget.store.sendTextToStudio(text);
          _openTab(1);
        },
      ),
      CommandsPage(store: widget.store),
    ];
    WidgetsBinding.instance.addPostFrameCallback((_) => _openPendingSection());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _automation.setPendingRequestListener(null);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _openPendingSection();
    }
  }

  Future<void> _openPendingSection() async {
    final studioRequest = await _automation.consumeStudioVoiceRequest();
    if (studioRequest != null) {
      await widget.store.queueStudioVoiceRequest(
        prompt: studioRequest.prompt,
        outputType: studioRequest.outputType,
        autoGenerate: studioRequest.autoGenerate,
      );
      _openTab(1);
      return;
    }

    final chatPrompt = await _automation.consumeChatVoiceRequest();
    if (chatPrompt != null) {
      widget.store.queueChatVoiceRequest(chatPrompt);
      _openTab(3);
      return;
    }

    final section = await _automation.consumeIronSection();
    if (section != null) {
      _openLegacySection(section);
    }
  }

  void _openLegacySection(int legacyIndex) {
    switch (legacyIndex) {
      case 0:
        _openTab(0);
        break;
      case 1:
        _openTab(1);
        break;
      case 2:
        _openTab(2);
        break;
      case 3:
        _openTab(3);
        break;
      case 4:
        _openTab(4);
        break;
    }
  }

  void _openTab(int index) {
    if (!mounted || index < 0 || index >= _pages.length) return;
    setState(() => _currentIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: IndexedStack(index: _currentIndex, children: _pages),
      bottomNavigationBar: IronBottomNavigation(
        selectedIndex: _currentIndex,
        onSelected: _openTab,
        items: _navItems,
      ),
    );
  }
}

class _IronHomeDashboard extends StatefulWidget {
  final LocalStore store;
  final VoidCallback onOpenChat;
  final VoidCallback onOpenStudio;
  final VoidCallback onOpenSongs;
  final VoidCallback onOpenVoice;
  final VoidCallback onOpenTools;

  const _IronHomeDashboard({
    required this.store,
    required this.onOpenChat,
    required this.onOpenStudio,
    required this.onOpenSongs,
    required this.onOpenVoice,
    required this.onOpenTools,
  });

  @override
  State<_IronHomeDashboard> createState() => _IronHomeDashboardState();
}

class _IronHomeDashboardState extends State<_IronHomeDashboard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IronBackground(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxHeight < 700;
          final horizontal = compact ? 12.0 : 16.0;
          final coreSize = (constraints.maxWidth * (compact ? 0.56 : 0.62))
              .clamp(compact ? 188.0 : 210.0, compact ? 220.0 : 258.0)
              .toDouble();

          return SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: EdgeInsets.fromLTRB(horizontal, 8, horizontal, 14),
            child: Column(
              children: [
                _HomeHeader(onMenu: widget.onOpenTools),
                SizedBox(height: compact ? 4 : 8),
                AnimatedBuilder(
                  animation: _pulseController,
                  builder: (context, _) => _HomeCoreFrame(
                    progress: _pulseController.value,
                    size: coreSize,
                  ),
                ),
                SizedBox(height: compact ? 6 : 10),
                AnimatedBuilder(
                  animation: widget.store,
                  builder: (context, _) => _HomeStatusCard(
                    hasProvider: widget.store.hasAnyAiProvider,
                    voiceEnabled: widget.store.voiceRepliesEnabled,
                  ),
                ),
                SizedBox(height: compact ? 12 : 16),
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: compact ? 1.48 : 1.58,
                  children: [
                    _HomeActionTile(
                      icon: Icons.chat_bubble_outline_rounded,
                      title: 'ЧАТ',
                      subtitle: 'Говори с AI',
                      onTap: widget.onOpenChat,
                    ),
                    _HomeActionTile(
                      icon: Icons.mic_external_on_rounded,
                      title: 'RAP STUDIO',
                      subtitle: 'Пиши и генерирай',
                      onTap: widget.onOpenStudio,
                    ),
                    _HomeActionTile(
                      icon: Icons.music_note_rounded,
                      title: 'ПЕСНИ',
                      subtitle: 'Моите проекти',
                      onTap: widget.onOpenSongs,
                    ),
                    _HomeActionTile(
                      icon: Icons.graphic_eq_rounded,
                      title: 'ГЛАС',
                      subtitle: 'BG микрофон',
                      onTap: widget.onOpenVoice,
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _HomeHeader extends StatelessWidget {
  final VoidCallback onMenu;

  const _HomeHeader({required this.onMenu});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 78,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: IconButton(
              tooltip: 'Настройки',
              onPressed: onMenu,
              icon: const Icon(Icons.menu_rounded, color: ironGreen, size: 30),
            ),
          ),
          const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'IRON MUSIC',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 23,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2.6,
                  height: 1.0,
                  shadows: [Shadow(color: Colors.black, blurRadius: 12)],
                ),
              ),
              SizedBox(height: 3),
              Text(
                '420 AI',
                style: TextStyle(
                  color: ironGreen,
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 4.0,
                  height: 1.0,
                  shadows: [Shadow(color: ironGreen, blurRadius: 16)],
                ),
              ),
              SizedBox(height: 5),
              Text(
                'ТВОЯТ AI РАП ПРОДУЦЕНТ',
                style: TextStyle(
                  color: ironGreenSoft,
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2.0,
                ),
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Container(
              width: 9,
              height: 9,
              margin: const EdgeInsets.only(right: 12),
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: ironGreen,
                boxShadow: [BoxShadow(color: ironGreen, blurRadius: 12)],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeCoreFrame extends StatelessWidget {
  final double progress;
  final double size;

  const _HomeCoreFrame({required this.progress, required this.size});

  @override
  Widget build(BuildContext context) {
    final outer = size + 34;
    return SizedBox(
      width: outer,
      height: outer,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: outer,
            height: outer,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: ironGreen.withOpacity(0.18 + progress * 0.20),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: ironGreen.withOpacity(0.08 + progress * 0.09),
                  blurRadius: 34 + progress * 18,
                  spreadRadius: 2,
                ),
              ],
            ),
          ),
          Container(
            width: size + 17,
            height: size + 17,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: ironGreenSoft.withOpacity(0.48 + progress * 0.28),
                width: 2.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: ironGreen.withOpacity(0.20 + progress * 0.14),
                  blurRadius: 18 + progress * 12,
                ),
                const BoxShadow(
                  color: Colors.black87,
                  blurRadius: 18,
                  offset: Offset(0, 10),
                ),
              ],
            ),
          ),
          CannabisCore(progress: progress, size: size),
          Positioned(
            bottom: 1,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF031108).withOpacity(0.96),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: ironGreen.withOpacity(0.55)),
                boxShadow: [
                  BoxShadow(color: ironGreen.withOpacity(0.18), blurRadius: 12),
                ],
              ),
              child: const Text(
                '420',
                style: TextStyle(
                  color: ironGreen,
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2.0,
                  shadows: [Shadow(color: ironGreen, blurRadius: 8)],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeStatusCard extends StatelessWidget {
  final bool hasProvider;
  final bool voiceEnabled;

  const _HomeStatusCard({
    required this.hasProvider,
    required this.voiceEnabled,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxWidth: 430),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: const Color(0xFF020D06).withOpacity(0.94),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: ironGreen.withOpacity(0.31)),
        boxShadow: [
          BoxShadow(color: ironGreen.withOpacity(0.06), blurRadius: 18),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: ironGreen.withOpacity(0.10),
              border: Border.all(color: ironGreen.withOpacity(0.46)),
            ),
            child: Icon(
              hasProvider ? Icons.verified_user_outlined : Icons.key_rounded,
              color: ironGreen,
              size: 19,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasProvider ? 'API КЛЮЧЪТ Е ЗАПАЗЕН' : 'ДОБАВИ API КЛЮЧ',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: ironGreen,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  voiceEnabled
                      ? 'Gemini / Groq • Български глас'
                      : 'AI е готов • гласът е изключен',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white60,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: hasProvider ? ironGreen : Colors.orangeAccent,
              boxShadow: [
                BoxShadow(
                  color: hasProvider ? ironGreen : Colors.orangeAccent,
                  blurRadius: 10,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _HomeActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(18);
    return Material(
      color: Colors.transparent,
      borderRadius: radius,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: radius,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFF0A2A15).withOpacity(0.98),
                const Color(0xFF031209).withOpacity(0.98),
                const Color(0xFF010703).withOpacity(0.99),
              ],
            ),
            border: Border.all(color: ironGreen.withOpacity(0.50), width: 1.2),
            boxShadow: [
              BoxShadow(
                color: ironGreen.withOpacity(0.11),
                blurRadius: 18,
                spreadRadius: 1,
              ),
              const BoxShadow(
                color: Colors.black54,
                blurRadius: 12,
                offset: Offset(0, 7),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(
              children: [
                Container(
                  width: 43,
                  height: 43,
                  decoration: BoxDecoration(
                    color: ironGreen.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(color: ironGreen.withOpacity(0.26)),
                  ),
                  child: Icon(
                    icon,
                    color: ironGreen,
                    size: 28,
                    shadows: const [Shadow(color: ironGreen, blurRadius: 10)],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.3,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 10.5,
                          height: 1.15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
'''

MAIN.write_text(main[:start] + replacement + '\n', encoding='utf-8')
print('Applied Build 68 reference dashboard: home HUD, exact gyro leaf, status card, 2x2 actions, five-tab navigation.')
