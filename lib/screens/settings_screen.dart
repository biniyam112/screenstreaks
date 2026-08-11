import 'dart:io';
import 'package:flutter/material.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import '../app_events.dart';
import '../data/repo_scope.dart';
import '../main_app.dart' show AuthScope;
import '../services/notifications.dart';
import '../services/prefs.dart';
import '../services/usage_service.dart';
import '../theme.dart';
import '../theme_provider.dart';
import '../widgets.dart';
import '../services/screen_time.dart';

/// Daily goal, alerts, appearance, usage-access (Android), and sign-out.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with WidgetsBindingObserver {
  int _goal = 120;
  final _first = TextEditingController();
  final _last = TextEditingController();
  final _nick = TextEditingController();
  bool _stHasApps = false;
  int _stLimit = 0; // current picker value (unsaved)
  int _savedGoal = 120; // last value persisted to the backend
  bool _notif = true;
  bool _hasPermission = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    final me = await RepoScope.of(context).me();
    if (!mounted) return;
    final notif = await Prefs.notificationsEnabled();
    final perm = await UsageService.hasPermission();
    // Prefs survives restarts; LocalRepository doesn't. Prefer the persisted
    // value so the UI matches what monitoring actually uses.
    final savedGoal = await Prefs.goalMinutes();
    if (!mounted) return;
    setState(() {
      _goal = savedGoal;
      _first.text = me.firstName ?? '';
      _last.text = me.lastName ?? '';
      _nick.text = me.nickname ?? '';
      _savedGoal = savedGoal;
      _notif = notif;
      _hasPermission = perm;
      _loaded = true;
    });
    _refreshScreenTime();
  }

  Future<void> _saveGoal() async {
    final m = _goal;
    await RepoScope.of(context).setDailyLimit(m);
    await Prefs.setGoalMinutes(m);
    if (!mounted) return;
    setState(() => _savedGoal = m);
    notifyProfileChanged(); // let the home tab refresh its big limit number
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Daily limit saved')),
    );
  }

  Future<void> _toggleNotif(bool v) async {
    setState(() => _notif = v);
    await Prefs.setNotificationsEnabled(v);
    if (v) await Notifications.requestPermission();
  }

  Future<void> _saveNames() async {
    final repo = RepoScope.of(context);
    await repo.setNames(
      firstName: _first.text.trim(),
      lastName: _last.text.trim(),
      nickname: _nick.text.trim(),
    );
    notifyProfileChanged();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Name saved')),
    );
  }

  Future<void> _stopTracking() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: c.cSurface,
        title: Text('Stop tracking?',
            style: appFont(fontWeight: FontWeight.w700, color: c.cText)),
        content: Text(
          "Today won't count toward your streak, and time while it's off is "
          'visible to your group.',
          style: appFont(fontWeight: FontWeight.w500, color: c.cTextSec),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text('Keep tracking',
                style: appFont(
                    color: c.cTextSec, fontWeight: FontWeight.w600)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text('Stop',
                style: appFont(
                    color: AppColors.danger, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final repo = RepoScope.of(context);
    await ScreenTime.stopMonitoring();
    await Prefs.setTrackingEnabled(false);
    await repo.logMonitoringOff('manual');
    await repo.checkIn(
      day: DateTime.now(),
      limitMet: false,
      limitMinutes: _savedGoal,
      source: 'manual',
      partial: true,
    );
    await _refreshScreenTime();
  }

  Future<void> _refreshScreenTime() async {
    final has = await ScreenTime.hasSelection();
    final active = await ScreenTime.activeLimit();
    if (!mounted) return;
    setState(() {
      _stHasApps = has;
      _stLimit = active;
    });
  }

  Future<void> _pickApps() async {
    await ScreenTime.requestAuthorization();
    final apps = await ScreenTime.pickApps();
    await _refreshScreenTime();
    if (apps > 0 || !mounted) return;

    // Category tokens alone don't reliably trigger a threshold, so a
    // category-only selection silently watches nothing.
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: c.cSurface,
        title: Text('Pick some apps too',
            style: appFont(fontWeight: FontWeight.w700, color: c.cText)),
        content: Text(
          "Categories on their own don't reliably count toward your limit. "
          'Open a category in the picker and select the apps inside it — '
          'the ones you actually lose time to.',
          style: appFont(fontWeight: FontWeight.w500, color: c.cTextSec),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: Text('Got it',
                style: appFont(
                    color: AppColors.primary, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Future<void> _startTracking() async {
    final ok = await ScreenTime.startMonitoring(_savedGoal);
    if (ok) await Prefs.setTrackingEnabled(true);
    await _refreshScreenTime();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? 'Tracking started' : "Couldn't start tracking")),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                _SectionLabel('Your name'),
                AppCard(
                  child: Column(
                    children: [
                      _SettingsField(controller: _first, hint: 'First name'),
                      const SizedBox(height: 10),
                      _SettingsField(controller: _last, hint: 'Last name'),
                      const SizedBox(height: 10),
                      _SettingsField(
                        controller: _nick,
                        hint: 'Widget nickname (4 characters)',
                        maxLength: 4,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        "Shown on the home-screen widget where there's no room "
                        'for a full name. Leave it blank to use your initials.',
                        style: appFont(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: context.cTextTer,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                ModernButton(
                  label: 'Save name',
                  icon: IconsaxPlusBold.tick_circle,
                  onPressed: _saveNames,
                ),
                const SizedBox(height: 24),
                _SectionLabel('Daily limit'),
                AppCard(
                  padding:
                      const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                  child: GoalPicker(
                    minutes: _goal,
                    onChanged: (m) => setState(() => _goal = m),
                  ),
                ),
                const SizedBox(height: 12),
                ModernButton(
                  label: 'Save daily limit',
                  icon: IconsaxPlusBold.tick_circle,
                  // Disabled until the picker differs from the saved value.
                  onPressed: _goal == _savedGoal ? null : _saveGoal,
                ),
                const SizedBox(height: 24),
                _SectionLabel('Alerts'),
                AppCard(
                  child: _SwitchRow(
                    icon: IconsaxPlusBold.notification_bing,
                    iconColor: AppColors.warning,
                    title: 'Approaching-limit alerts',
                    subtitle: 'Get notified as you near your daily limit.',
                    value: _notif,
                    onChanged: _toggleNotif,
                  ),
                ),
                const SizedBox(height: 24),
                _SectionLabel('Appearance'),
                AppCard(
                  child: _SwitchRow(
                    icon: ThemeScope.of(context).isDark
                        ? IconsaxPlusBold.moon
                        : IconsaxPlusBold.sun_1,
                    iconColor: AppColors.info,
                    title: 'Dark theme',
                    subtitle: 'Switch between dark and light mode.',
                    value: ThemeScope.of(context).isDark,
                    onChanged: (_) => ThemeScope.of(context).toggleTheme(),
                  ),
                ),
                if (ScreenTime.supported && _stLimit > 0) ...[
                  const SizedBox(height: 34),
                  AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Stop tracking',
                          style: appFont(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: context.cText,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          "Today won't count either way, and your group sees "
                          'the gap. You can turn it back on any time.',
                          style: appFont(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                            color: context.cTextSec,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 12),
                        GestureDetector(
                          onTap: _stopTracking,
                          child: Text(
                            'Stop tracking',
                            style: appFont(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.danger,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (ScreenTime.supported) ...[
                  const SizedBox(height: 24),
                  _SectionLabel('Screen Time'),
                  AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _stLimit > 0
                              ? 'Tracking automatically. iOS tells the app when '
                                  'you pass your limit — nothing else is shared.'
                              : 'Let iOS track this for you. Pick which apps '
                                  'count, and your days log themselves.',
                          style: appFont(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w500,
                            color: context.cTextSec,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 14),
                        ModernButton(
                          label: _stHasApps ? 'Change apps' : 'Choose apps',
                          onPressed: _pickApps,
                        ),
                        const SizedBox(height: 10),
                        ModernButton(
                          label: _stLimit > 0 ? 'Restart tracking' : 'Start tracking',
                          onPressed: _stHasApps ? _startTracking : null,
                        ),
                        const SizedBox(height: 10),
                        // TEMPORARY: 2-minute threshold for testing. Remove.
                        ModernButton(
                          label: 'TEST · track 2 minutes',
                          onPressed: _stHasApps
                              ? () async {
                                  await ScreenTime.startMonitoring(2);
                                  await _refreshScreenTime();
                                }
                              : null,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Deleting Undr stops tracking. Days it missed '
                          "won't count, and your streak may break.",
                          style: appFont(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: context.cTextTer,
                            height: 1.4,
                          ),
                        ),
                        if (_stLimit > 0) ...[
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              const Icon(IconsaxPlusBold.tick_circle,
                                  size: 16, color: AppColors.primary),
                              const SizedBox(width: 6),
                              Text(
                                'Watching ${_stLimit ~/ 60}h ${_stLimit % 60}m',
                                style: appFont(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: context.cTextSec,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
                if (Platform.isAndroid) ...[
                  const SizedBox(height: 24),
                  _SectionLabel('Automatic tracking'),
                  AppCard(
                    child: Row(
                      children: [
                        Icon(
                          _hasPermission
                              ? IconsaxPlusBold.tick_circle
                              : IconsaxPlusBold.info_circle,
                          color: _hasPermission
                              ? AppColors.primary
                              : AppColors.warning,
                          size: 22,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Usage access',
                                style: appFont(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                  color: context.cText,
                                ),
                              ),
                              Text(
                                _hasPermission
                                    ? 'On — days log automatically'
                                    : 'Off — grant to auto-track',
                                style: appFont(
                                  color: context.cTextSec,
                                  fontWeight: FontWeight.w500,
                                  fontSize: 12.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (!_hasPermission)
                          ModernButton(
                            label: 'Grant',
                            expand: false,
                            color: AppColors.info,
                            onPressed: () => UsageService.requestPermission(),
                          ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 32),
                ModernButton(
                  label: 'Sign out',
                  icon: IconsaxPlusLinear.logout,
                  outlined: true,
                  textColor: AppColors.danger,
                  onPressed: () async {
                    final auth = AuthScope.of(context);
                    Navigator.of(context).pop();
                    await auth.signOut();
                  },
                ),
              ],
            ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final Color iconColor;
  final String title, subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: iconColor, size: 22),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: appFont(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: context.cText,
                ),
              ),
              Text(
                subtitle,
                style: appFont(
                  color: context.cTextSec,
                  fontWeight: FontWeight.w500,
                  fontSize: 12.5,
                ),
              ),
            ],
          ),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          activeThumbColor: Colors.white,
          activeTrackColor: AppColors.primary,
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 10),
      child: Text(
        text.toUpperCase(),
        style: appFont(
          color: context.cTextTer,
          fontWeight: FontWeight.w700,
          fontSize: 12,
          letterSpacing: 1,
        ),
      ),
    );
  }
}

/// Compact text field for the settings form.
class _SettingsField extends StatelessWidget {
  const _SettingsField({
    required this.controller,
    required this.hint,
    this.maxLength,
  });

  final TextEditingController controller;
  final String hint;
  final int? maxLength;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      textCapitalization: TextCapitalization.words,
      maxLength: maxLength,
      style: appFont(
          fontSize: 15, fontWeight: FontWeight.w600, color: context.cText),
      decoration: InputDecoration(
        hintText: hint,
        counterText: '',
        isDense: true,
        hintStyle: appFont(
            fontSize: 15, fontWeight: FontWeight.w500, color: context.cTextTer),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: context.cDivider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
      ),
    );
  }
}
