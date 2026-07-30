import 'package:flutter/material.dart';

import 'pages/chat_page.dart';
import 'pages/commands_page.dart';
import 'pages/home_page.dart';
import 'pages/rap_studio_page.dart';
import 'pages/songs_page.dart';
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

class _MainScreenState extends State<MainScreen> {
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
      label: 'Studio',
    ),
    IronNavItem(
      icon: Icons.library_music_outlined,
      selectedIcon: Icons.library_music,
      label: 'Песни',
    ),
    IronNavItem(
      icon: Icons.chat_bubble_outline,
      selectedIcon: Icons.chat_bubble,
      label: 'Чат',
    ),
    IronNavItem(
      icon: Icons.settings_outlined,
      selectedIcon: Icons.settings,
      label: 'Автоматизации',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _pages = [
      HomePage(
        store: widget.store,
        onOpenSection: _openSection,
      ),
      RapStudioPage(store: widget.store),
      SongsPage(
        store: widget.store,
        onOpenStudio: () => _openSection(1),
      ),
      ChatPage(store: widget.store),
      CommandsPage(
        store: widget.store,
        onOpenSection: _openSection,
      ),
    ];
  }

  void _openSection(int index) {
    if (!mounted || index < 0 || index >= _pages.length) return;
    setState(() => _currentIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
      ),
      bottomNavigationBar: IronBottomNavigation(
        selectedIndex: _currentIndex,
        onSelected: _openSection,
        items: _navItems,
      ),
    );
  }
}
