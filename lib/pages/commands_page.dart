import 'package:flutter/material.dart';

import '../services/automation_service.dart';
import '../services/local_store.dart';
import '../ui/common_widgets.dart';

class CommandsPage extends StatefulWidget {
  final LocalStore store;
  final ValueChanged<int> onOpenSection;

  const CommandsPage({
    super.key,
    required this.store,
    required this.onOpenSection,
  });

  @override
  State<CommandsPage> createState() => _CommandsPageState();
}

class _CommandsPageState extends State<CommandsPage>
    with WidgetsBindingObserver {
  final AutomationService _automation = AutomationService();
  bool _ironActive = false;
  bool _busy = false;
  bool _flashlightOn = false;
  bool _youtubeAutoPlayEnabled = false;

  static const _primaryActions = <_ToolAction>[
    _ToolAction('youtube', 'YouTube', Icons.play_circle_outline_rounded),
    _ToolAction('camera', 'Камера', Icons.camera_alt_outlined),
    _ToolAction('maps', 'Карти', Icons.map_outlined),
    _ToolAction('flash_toggle', 'Фенер', Icons.flashlight_on_outlined),
    _ToolAction('volume_up', 'Звук +', Icons.volume_up_rounded),
    _ToolAction('settings', 'Настройки', Icons.settings_outlined),
  ];

  static const _moreActions = <_ToolAction>[
    _ToolAction('alarms', 'Аларми', Icons.alarm_outlined),
    _ToolAction('calendar', 'Календар', Icons.calendar_month_outlined),
    _ToolAction('dialer', 'Телефон', Icons.phone_outlined),
    _ToolAction('wifi', 'Wi‑Fi', Icons.wifi_rounded),
    _ToolAction('bluetooth', 'Bluetooth', Icons.bluetooth_rounded),
    _ToolAction('chrome', 'Браузър', Icons.language_rounded),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadStatus());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _loadStatus();
  }

  Future<void> _loadStatus() async {
    final results = await Future.wait<Object?>([
      _automation.isIronVoiceActive(),
      _automation.flashlightState(),
      _automation.isYoutubeAutoPlayEnabled(),
    ]);
    if (!mounted) return;
    setState(() {
      _ironActive = results[0] as bool;
      final flashlightState = results[1] as bool?;
      if (flashlightState != null) _flashlightOn = flashlightState;
      _youtubeAutoPlayEnabled = results[2] as bool;
    });
  }

  Future<void> _openYoutubeAutoPlaySettings() async {
    if (_busy) return;
    setState(() => _busy = true);
    final result = await _automation.openYoutubeAutoPlaySettings();
    if (!mounted) return;
    setState(() => _busy = false);
    _show(result);
  }

  Future<void> _toggleIron() async {
    if (_busy) return;
    setState(() => _busy = true);
    final result = await _automation.execute(
      _ironActive ? 'iron_voice_off' : 'iron_voice_on',
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (result.success) _ironActive = !_ironActive;
    });
    _show(result);
  }

  Future<void> _run(String action) async {
    if (_busy) return;
    setState(() => _busy = true);

    var resolved = action;
    if (action == 'flash_toggle') {
      final nativeState = await _automation.flashlightState();
      if (!mounted) return;
      resolved = (nativeState ?? _flashlightOn) ? 'flash_off' : 'flash_on';
    }
    final result = await _automation.execute(resolved);

    if (!mounted) return;
    setState(() {
      _busy = false;
      if (result.success && resolved == 'flash_on') _flashlightOn = true;
      if (result.success && resolved == 'flash_off') _flashlightOn = false;
    });
    _show(result);
  }

  void _show(AutomationResult result) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result.message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return IronBackground(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 108),
        children: [
          const PageTitle(
            eyebrow: 'IRON',
            title: 'Инструменти',
            subtitle: 'Само най-полезните действия. Останалото го кажи на AI.',
          ),
          const SizedBox(height: 18),
          IronCard(
            bright: _ironActive,
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: (_ironActive ? ironGreen : Colors.white)
                            .withOpacity(0.10),
                      ),
                      child: Icon(
                        _ironActive
                            ? Icons.hearing_rounded
                            : Icons.hearing_disabled_rounded,
                        color: _ironActive ? ironGreen : Colors.white54,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _ironActive ? 'Iron е активен' : 'Iron е спрян',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _ironActive
                                ? 'Кажи „Hey Iron“ и говори нормално.'
                                : 'Активирай фоновото гласово събуждане.',
                            style: const TextStyle(
                              color: Colors.white60,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                IronButton(
                  text: _ironActive ? 'СПРИ IRON' : 'АКТИВИРАЙ IRON',
                  icon: _ironActive
                      ? Icons.stop_circle_outlined
                      : Icons.play_circle_outline_rounded,
                  secondary: _ironActive,
                  onPressed: _busy ? null : _toggleIron,
                ),
              ],
            ),
          ),
          IronCard(
            bright: _youtubeAutoPlayEnabled,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(
                      _youtubeAutoPlayEnabled
                          ? Icons.play_circle_fill_rounded
                          : Icons.play_circle_outline_rounded,
                      color: _youtubeAutoPlayEnabled
                          ? ironGreen
                          : Colors.orangeAccent,
                      size: 30,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _youtubeAutoPlayEnabled
                            ? 'Автоматичното пускане е включено'
                            : 'Автоматично пускане в YouTube',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  'След твоя гласова команда Iron вижда само резултатите в YouTube за до 15 секунди и натиска първия подходящ клип. Не чете други приложения и не запазва съдържанието на екрана.',
                  style: TextStyle(
                    color: Colors.white70,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 14),
                IronButton(
                  text: _youtubeAutoPlayEnabled
                      ? 'ОТВОРИ НАСТРОЙКАТА'
                      : 'ВКЛЮЧИ В ДОСТЪПНОСТ',
                  icon: Icons.accessibility_new_rounded,
                  secondary: _youtubeAutoPlayEnabled,
                  onPressed: _busy ? null : _openYoutubeAutoPlaySettings,
                ),
              ],
            ),
          ),
          IronButton(
            text: 'ОТВОРИ AI РАЗГОВОРА',
            icon: Icons.forum_rounded,
            onPressed: () => widget.onOpenSection(3),
          ),
          const SizedBox(height: 20),
          const Text(
            'Бързи действия',
            style: TextStyle(
              color: Colors.white,
              fontSize: 19,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _primaryActions.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.55,
            ),
            itemBuilder: (context, index) {
              final item = _primaryActions[index];
              final icon = item.action == 'flash_toggle' && _flashlightOn
                  ? Icons.flashlight_off_outlined
                  : item.icon;
              return _ToolTile(
                icon: icon,
                title: item.title,
                onTap: _busy ? null : () => _run(item.action),
              );
            },
          ),
          const SizedBox(height: 12),
          IronCard(
            padding: EdgeInsets.zero,
            child: ExpansionTile(
              title: const Text(
                'Още действия',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
              iconColor: ironGreen,
              collapsedIconColor: ironGreen,
              childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              children: [
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _moreActions.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    childAspectRatio: 1.75,
                  ),
                  itemBuilder: (context, index) {
                    final item = _moreActions[index];
                    return _ToolTile(
                      icon: item.icon,
                      title: item.title,
                      compact: true,
                      onTap: _busy ? null : () => _run(item.action),
                    );
                  },
                ),
              ],
            ),
          ),
          IronCard(
            child: Row(
              children: [
                Icon(
                  widget.store.hasApiKey
                      ? Icons.auto_awesome_rounded
                      : Icons.key_off_outlined,
                  color: widget.store.hasApiKey
                      ? ironGreen
                      : Colors.orangeAccent,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.store.hasApiKey
                        ? 'AI режимът е готов. За търсене, разговор и сложни заявки просто говори с Iron.'
                        : 'Запази Gemini API ключ в AI разговора, за да работят свободните заявки.',
                    style: const TextStyle(
                      color: Colors.white70,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ToolAction {
  final String action;
  final String title;
  final IconData icon;

  const _ToolAction(this.action, this.title, this.icon);
}

class _ToolTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback? onTap;
  final bool compact;

  const _ToolTile({
    required this.icon,
    required this.title,
    required this.onTap,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          decoration: BoxDecoration(
            color: ironPanelRaised.withOpacity(onTap == null ? 0.45 : 0.92),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: ironGreen.withOpacity(0.30)),
          ),
          child: compact
              ? Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, color: ironGreen, size: 20),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        title,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                )
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, color: ironGreen, size: 27),
                    const SizedBox(height: 8),
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
