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

/// Daily goal, alerts, appearance, usage-access (Android), and sign-out.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with WidgetsBindingObserver {
  int _goal = 120; // current picker value (unsaved)
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
    final notif = await Prefs.notificationsEnabled();
    final perm = await UsageService.hasPermission();
    // Prefs survives restarts; LocalRepository doesn't. Prefer the persisted
    // value so the UI matches what monitoring actually uses.
    final savedGoal = await Prefs.goalMinutes();
    if (!mounted) return;
    setState(() {
      _goal = savedGoal;
      _savedGoal = savedGoal;
      _notif = notif;
      _hasPermission = perm;
      _loaded = true;
    });
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
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
