import 'package:flutter/material.dart';

import 'pages/chat_page.dart';
import 'pages/onboarding_page.dart';
import 'pages/rap_studio_page.dart';
import 'pages/settings_page.dart';
import 'pages/songs_page.dart';
import 'services/automation_service.dart';
import 'services/local_store.dart';
import 'theme/iron_theme.dart';
import 'ui/common_widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  ErrorWidget.builder = (details) => Material(
        color: ironDark,
        child: IronBackground(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: IronCard(
                bright: true,
                child: const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.warning_amber, color: ironGreen, size: 52),
                    SizedBox(height: 14),
                    Text(
                      'Възникна проблем с този екран.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Затвори приложението и го отвори отново. Данните ти остават запазени локално.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

  final store = LocalStore();
  await store.initialize();
  runApp(IronMusic420App(store: store));
}

class IronMusic420App extends StatelessWidget {
  final LocalStore store;

  const IronMusic420App({super.key, required this.store});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Iron Music 420 AI',
          theme: ironTheme(),
          builder: (context, child) {
            final media = MediaQuery.of(context);
            final currentScale = media.textScaler.scale(1.0);
            final safeScale = currentScale.clamp(0.85, 1.3).toDouble();
            return MediaQuery(
              data: media.copyWith(textScaler: TextScaler.linear(safeScale)),
              child: child ?? const SizedBox.shrink(),
            );
          },
          home: store.onboardingComplete
              ? MainScreen(store: store)
              : OnboardingPage(store: store),
        );
      },
    );
  }
}

class MainScreen extends StatefulWidget {
  final LocalStore store;

  const MainScreen({super.key, required this.store});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  final AutomationService _automation = AutomationService();
  int _currentIndex = 0;
  late List<Widget> _pages;
  static const int _tabCount = 4;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _automation.setPendingRequestListener(_openPendingSection);
    _rebuildPages();
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
      _openSection(1);
      return;
    }

    final chatPrompt = await _automation.consumeChatVoiceRequest();
    if (chatPrompt != null) {
      widget.store.queueChatVoiceRequest(chatPrompt);
      _openSection(3);
      return;
    }

    final section = await _automation.consumeIronSection();
    if (section != null) {
      _openSection(section);
    }
  }

  void _openSection(int legacyIndex) {
    if (!mounted) return;

    int targetIndex;
    switch (legacyIndex) {
      case 0:
      case 3:
        targetIndex = 0;
        break;
      case 1:
        targetIndex = 1;
        break;
      case 2:
        targetIndex = 2;
        break;
      case 4:
        targetIndex = 3;
        break;
      default:
        return;
    }

    _selectTab(targetIndex);
  }

  void _selectTab(int index) {
    if (!mounted || index < 0 || index >= _tabCount) return;
    setState(() {
      _currentIndex = index;
      _rebuildPages();
    });
  }

  void _rebuildPages() {
    _pages = [
      ChatPage(
        store: widget.store,
        isActive: _currentIndex == 0,
        onOpenTools: () => _openSection(4),
        onOpenSettings: () => _selectTab(3),
        onSendToStudio: (text) async {
          await widget.store.sendTextToStudio(text);
          _openSection(1);
        },
      ),
      RapStudioPage(store: widget.store),
      SongsPage(store: widget.store, onOpenStudio: () => _openSection(1)),
      SettingsPage(
        store: widget.store,
        onOpenChat: () => _selectTab(0),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: IndexedStack(index: _currentIndex, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: _selectTab,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.auto_awesome_outlined),
            selectedIcon: Icon(Icons.auto_awesome_rounded),
            label: 'Хей Айрън',
          ),
          NavigationDestination(
            icon: Icon(Icons.mic_external_on_outlined),
            selectedIcon: Icon(Icons.mic_external_on),
            label: 'Студио',
          ),
          NavigationDestination(
            icon: Icon(Icons.library_music_outlined),
            selectedIcon: Icon(Icons.library_music),
            label: 'Песни',
          ),
          NavigationDestination(
            icon: Icon(Icons.tune_outlined),
            selectedIcon: Icon(Icons.tune_rounded),
            label: 'Настройки',
          ),
        ],
      ),
    );
  }
}
