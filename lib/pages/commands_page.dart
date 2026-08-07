import 'package:flutter/material.dart';

import '../services/automation_service.dart';
import '../services/local_store.dart';
import '../ui/common_widgets.dart';

class CommandsPage extends StatefulWidget {
  final LocalStore store;

  const CommandsPage({
    super.key,
    required this.store,
  });

  @override
  State<CommandsPage> createState() => _CommandsPageState();
}

class _CommandsPageState extends State<CommandsPage>
    with WidgetsBindingObserver {
  final AutomationService _automation = AutomationService();
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
      _automation.flashlightState(),
      _automation.isYoutubeAutoPlayEnabled(),
    ]);
    if (!mounted) return;
    setState(() {
      final flashlightState = results[0] as bool?;
      if (flashlightState != null) _flashlightOn = flashlightState;
      _youtubeAutoPlayEnabled = results[1] as bool;
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
            subtitle:
                'Само най-полезните действия. Останалото го кажи на Хей Айрън.',
          ),
          const SizedBox(height: 18),
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
          const SizedBox(height: 8),
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
                  widget.store.hasAnyAiProvider
                      ? Icons.auto_awesome_rounded
                      : Icons.key_off_outlined,
                  color: widget.store.hasAnyAiProvider
                      ? ironGreen
                      : Colors.orangeAccent,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.store.hasAnyAiProvider
                        ? 'Хей Айрън е готов. За разговор и сложни заявки говори или пиши в чата.'
                        : 'Запази Gemini API ключ в Хей Айрън, за да работят свободните заявки.',
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
