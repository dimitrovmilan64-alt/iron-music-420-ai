import 'package:flutter/material.dart';

import 'pages/chat_page.dart';
import 'pages/commands_page.dart';
import 'pages/rap_studio_page.dart';
import 'pages/songs_page.dart';
import 'services/automation_service.dart';
import 'services/local_store.dart';
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
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Iron Music 420 AI',
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        scaffoldBackgroundColor: ironDark,
        fontFamily: 'Roboto',
        colorScheme: const ColorScheme.dark(
          primary: ironGreen,
          secondary: ironGreenSoft,
          surface: ironPanel,
          error: Color(0xFFFF745C),
        ),
        dividerColor: Colors.white12,
        iconTheme: const IconThemeData(color: Colors.white70),
        popupMenuTheme: PopupMenuThemeData(
          color: ironPanelRaised,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: ironGreen.withOpacity(0.24)),
          ),
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: ironPanelRaised,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
            side: BorderSide(color: ironGreen.withOpacity(0.28)),
          ),
        ),
        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: Color(0xFF031108),
          modalBackgroundColor: Color(0xFF031108),
        ),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          backgroundColor: ironPanelRaised,
          contentTextStyle: const TextStyle(color: Colors.white),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: ironGreen.withOpacity(0.25)),
          ),
        ),
        sliderTheme: SliderThemeData(
          activeTrackColor: ironGreen,
          inactiveTrackColor: ironGreen.withOpacity(0.16),
          thumbColor: ironGreenSoft,
          overlayColor: ironGreen.withOpacity(0.12),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: ironGreen,
            foregroundColor: Colors.black,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: ironGreen,
            side: BorderSide(color: ironGreen.withOpacity(0.45)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF010A05).withOpacity(0.94),
          labelStyle: const TextStyle(color: ironGreen),
          hintStyle: const TextStyle(color: Colors.white30),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(17),
            borderSide: BorderSide(color: ironGreen.withOpacity(0.28)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(17),
            borderSide: const BorderSide(color: ironGreen, width: 1.6),
          ),
        ),
      ),
      builder: (context, child) {
        final media = MediaQuery.of(context);
        final currentScale = media.textScaler.scale(1.0);
        final safeScale = currentScale.clamp(0.90, 1.0).toDouble();
        return MediaQuery(
          data: media.copyWith(textScaler: TextScaler.linear(safeScale)),
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: MainScreen(store: store),
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
  late final List<Widget> _pages;

  static const _navItems = <IronNavItem>[
    IronNavItem(
      icon: Icons.auto_awesome_outlined,
      selectedIcon: Icons.auto_awesome_rounded,
      label: 'Хей Айрън',
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
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _automation.setPendingRequestListener(_openPendingSection);
    _pages = [
      ChatPage(
        store: widget.store,
        onOpenTools: () => _openSection(4),
        onSendToStudio: (text) async {
          await widget.store.sendTextToStudio(text);
          _openSection(1);
        },
      ),
      RapStudioPage(store: widget.store),
      SongsPage(store: widget.store, onOpenStudio: () => _openSection(1)),
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

    setState(() => _currentIndex = targetIndex);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: IndexedStack(index: _currentIndex, children: _pages),
      bottomNavigationBar: IronBottomNavigation(
        selectedIndex: _currentIndex < _navItems.length ? _currentIndex : 0,
        onSelected: _openSection,
        items: _navItems,
      ),
    );
  }
}
