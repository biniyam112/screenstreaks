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
import '../models/models.dart';
import 'log_screen.dart';

/// Daily goal, alerts, appearance, usage-access (Android), and sign-out.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with WidgetsBindingObserver {
  int _goal = 120;
  int? _pendingGoal;
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
    final pendingGoal = await Prefs.pendingGoal();
    if (!mounted) return;
    setState(() {
      _goal = savedGoal;
      _pendingGoal = pendingGoal;
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

    // Changing the limit restarts the threshold count from zero, wiping
    // today's progress — so a change while tracking waits for midnight.
    if (_stLimit > 0) {
      final oldH = _savedGoal ~/ 60;
      final oldM = _savedGoal % 60;
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          backgroundColor: c.cSurface,
          title: Text('Starts tomorrow',
              style: appFont(fontWeight: FontWeight.w700, color: c.cText)),
          content: Text(
            "Today's count is already running, so a new limit can't judge it "
            'fairly. This takes effect at midnight — today stays on '
            '${oldH}h${oldM == 0 ? '' : oldM}.',
            style: appFont(fontWeight: FontWeight.w500, color: c.cTextSec),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: Text('Cancel',
                  style: appFont(
                      color: c.cTextSec, fontWeight: FontWeight.w600)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text('Set for tomorrow',
                  style: appFont(
                      color: AppColors.primary, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
      await Prefs.setPendingGoal(m);
      // The extension applies this at midnight, so the new limit is live
      // from the start of the day rather than when the app next opens.
      await ScreenTime.setPendingLimit(m);
      setState(() {
        _pendingGoal = m;
        _goal = _savedGoal;
      });
      return;
    }

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
    // The plugin has to be initialised before it can ask for anything —
    // otherwise requestPermissions returns false without prompting.
    if (v) {
      await ScreenTime.authorizeNotifications();
      await Notifications.init();
      await Notifications.requestPermission();
    }
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
          "Days we can't watch don't count toward your streak — it won't "
          "advance, and your group sees the gap. If you're already over "
          'today, that stays.',
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
    // Only mark the day unjudged if it hadn't already been decided —
    // stopping after going over shouldn't erase the miss.
    final me = await repo.me();
    final today = dateOnly(DateTime.now());
    final existing = me.byDay[today];
    if (existing == null || existing.limitMet) {
      await repo.checkIn(
        day: DateTime.now(),
        limitMet: false,
        limitMinutes: _savedGoal,
        source: 'manual',
        partial: true,
      );
    }
    // My Streak keeps its own copy of the tracking state, so tell it to
    // reload or the pill still reads as live.
    notifyProfileChanged();
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
    final outcome = await ScreenTime.pickAppsDetailed();
    await _refreshScreenTime();
    if (!mounted) return;

    // Changing what's watched mid-day would restart the count from zero, so
    // it waits for midnight — say so, or the old selection looks like the
    // change didn't save.
    if (outcome.deferred) {
      await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          backgroundColor: c.cSurface,
          title: Text('Starts tomorrow',
              style: appFont(fontWeight: FontWeight.w700, color: c.cText)),
          content: Text(
            "Today's count is already running against your current apps, so "
            'changing them now would wipe it. Your new selection takes effect '
            'at midnight.',
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
                _SectionLabel('Account'),
                AppCard(
                  child: Row(
                    children: [
                      Icon(IconsaxPlusBold.sms,
                          size: 18, color: context.cTextSec),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          RepoScope.of(context).currentEmail ?? 'Not signed in',
                          style: appFont(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: context.cText,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
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
                if (_pendingGoal != null && _pendingGoal != _savedGoal) ...[
                  const SizedBox(height: 10),
                  Text(
                    'New limit of ${_pendingGoal! ~/ 60}h'
                    '${_pendingGoal! % 60 == 0 ? '' : _pendingGoal! % 60}'
                    ' starts tomorrow.',
                    style: appFont(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.accent,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                if (ScreenTime.supported)
                  ModernButton(
                    label: 'Activity log',
                    icon: IconsaxPlusBold.document_text,
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const LogScreen()),
                    ),
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
                        _SwitchRow(
                          icon: IconsaxPlusBold.mobile,
                          iconColor: AppColors.primary,
                          title: 'Track my screen time',
                          subtitle: _stLimit > 0
                              ? 'Watching ${_stLimit ~/ 60}h ${_stLimit % 60}m'
                              : 'Off — days it misses won\'t count',
                          value: _stLimit > 0,
                          onChanged: (on) {
                            // No apps chosen yet — send them to the picker
                            // rather than starting a monitor watching nothing.
                            // Only send them to the picker when turning it
                            // on — switching off should just stop.
                            if (on && !_stHasApps) {
                              _pickApps();
                              return;
                            }
                            if (on) {
                              _startTracking();
                            } else {
                              _stopTracking();
                            }
                          },
                        ),
                        const SizedBox(height: 10),
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
