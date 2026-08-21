import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import '../app_events.dart';
import '../data/repo_scope.dart';
import '../services/prefs.dart';
import '../theme.dart';
import '../widgets.dart';
import '../services/screen_time.dart';

/// First-run setup shown once after a new sign-up:
///   1. set your daily screen-time limit
///   2. confirm your name (prefilled from Google)
/// then hands off to the home shell.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pageController = PageController();
  final _firstController = TextEditingController();
  final _lastController = TextEditingController();
  final _nicknameController = TextEditingController();

  int _page = 0;
  bool _alerts = false;
  bool _tracking = false;
  int _limit = 120;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _prefill();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _firstController.dispose();
    _lastController.dispose();
    _nicknameController.dispose();
    super.dispose();
  }

  Future<void> _prefill() async {
    final repo = RepoScope.of(context);
    try {
      final me = await repo.me();
      final savedGoal = await Prefs.goalMinutes();
      if (!mounted) return;
      setState(() {
        _limit = savedGoal;
        // Google name lands here via sign-in; blank if it was the default.
        // Prefilled from Google when that's how they signed in.
        final parts = me.displayName == 'Friend'
            ? const <String>[]
            : me.displayName.trim().split(RegExp(r'\s+'));
        _firstController.text = parts.isNotEmpty ? parts.first : '';
        _lastController.text = parts.length > 1 ? parts.last : '';
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _next() {
    final target = _page + 1;
    setState(() => _page = target);
    _pageController.animateToPage(
      target,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  void _back() {
    final target = _page - 1;
    setState(() => _page = target);
    _pageController.animateToPage(
      target,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  /// Ask for Screen Time access and start watching the chosen limit. If the
  /// user declines we carry on — they can turn it on later in Settings.
  /// The warning event is useless if iOS never shows it, and the toggle
  /// buried in Settings is easy to miss.
  Future<void> _enableAlerts() async {
    final status = await ScreenTime.notificationStatus();

    // iOS shows its prompt once. If it's already been answered, the button
    // would silently do nothing — so send them to Settings instead.
    if (status != 'ask') {
      await Prefs.setNotificationsEnabled(status == 'on');
      if (!mounted) return;
      setState(() => _alerts = status == 'on');
      await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          backgroundColor: c.cSheet,
          title: Text(status == 'on' ? 'Alerts are already on' : 'Alerts are off',
              style: appFont(fontWeight: FontWeight.w700, color: c.cText)),
          content: Text(
            status == 'on'
                ? "You'll hear from Undr when you're near your limit. You can "
                    'change that in iOS Settings.'
                : 'iOS has alerts turned off for Undr. You can turn them back '
                    'on in Settings.',
            style: appFont(fontWeight: FontWeight.w500, color: c.cTextSec),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: Text('Not now',
                  style: appFont(
                      color: c.cTextSec, fontWeight: FontWeight.w600)),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(c);
                launchUrl(Uri.parse('app-settings:'));
              },
              child: Text('Open Settings',
                  style: appFont(
                      color: AppColors.primary, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      );
      return;
    }

    final granted = await ScreenTime.authorizeNotifications();
    await Prefs.setNotificationsEnabled(granted);
    if (mounted) setState(() => _alerts = granted);
  }

  Future<void> _enableTracking() async {
    final ok = await ScreenTime.requestAuthorization();
    if (!ok || !mounted) return;
    await ScreenTime.pickApps();
    if (!mounted) return;

    final started = await ScreenTime.startMonitoring(_limit);
    if (mounted) setState(() => _tracking = started);
  }

  bool get _hasName =>
      _firstController.text.trim().isNotEmpty;

  Future<void> _finish() async {
    if (!_hasName) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter at least a first name.')),
      );
      return;
    }

    final first = _firstController.text.trim();
    final last = _lastController.text.trim();
    final nick = _nicknameController.text.trim();
    final name = [first, last].where((x) => x.isNotEmpty).join(' ');
    setState(() => _saving = true);
    final repo = RepoScope.of(context);
    try {
      await repo.setDailyLimit(_limit);
      await Prefs.setGoalMinutes(_limit);
      if (first.isNotEmpty || last.isNotEmpty || nick.isNotEmpty) {
        await repo.setNames(
          firstName: first,
          lastName: last,
          nickname: nick,
        );
      }
      await repo.setDisplayName(name.isNotEmpty ? name : first);
      await Prefs.setOnboarded(true);
      final uid = RepoScope.of(context).currentUserId;
      if (uid != null) {
        await Prefs.setOnboardedUser(uid);
        // Claim the monitor too, or My Streak's owner check sees the previous
        // account and clears the selection this screen just set.
        await Prefs.setMonitorOwner(uid);
      }
      await RepoScope.of(context).markOnboarded();
      notifyProfileChanged();
      if (!mounted) return;
      widget.onDone();
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save. Check connection.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Column(
          children: [
            // Progress dots + back.
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 20, 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 40,
                    child: _page == 1
                        ? IconButton(
                            onPressed: _back,
                            icon: const Icon(IconsaxPlusLinear.arrow_left_2),
                          )
                        : null,
                  ),
                  const Spacer(),
                  _Dot(active: _page == 0),
                  const SizedBox(width: 6),
                  _Dot(active: _page == 1),
                  if (ScreenTime.supported) ...[
                    const SizedBox(width: 6),
                    _Dot(active: _page == 2),
                  if (ScreenTime.supported) const SizedBox(width: 6),
                  if (ScreenTime.supported) _Dot(active: _page == 3),
                  ],
                  const Spacer(),
                  const SizedBox(width: 40),
                ],
              ),
            ),
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _LimitPage(
                    limit: _limit,
                    onChanged: (v) => setState(() => _limit = v),
                  ),
                  _NamePage(
                    first: _firstController,
                    last: _lastController,
                    nickname: _nicknameController,
                    onChanged: () => setState(() {}),
                  ),
                  if (ScreenTime.supported)
                    _TrackingPage(
                      enabled: _tracking,
                      onEnable: _enableTracking,
                    ),
                  if (ScreenTime.supported)
                    _AlertsPage(
                      enabled: _alerts,
                      onEnable: _enableAlerts,
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              child: _page < (ScreenTime.supported ? 3 : 1)
                  ? ModernButton(
                      label: 'Continue',
                      icon: IconsaxPlusBold.arrow_right_3,
                      // The name page needs both names before moving on —
                      // lists and the widget both depend on them.
                      onPressed: _page == 1 && !_hasName ? null : _next,
                    )
                  : ModernButton(
                      label: _saving ? 'Setting up…' : 'Get started',
                      onPressed: _saving ? null : _finish,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.active});
  final bool active;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      width: active ? 22 : 8,
      height: 8,
      decoration: BoxDecoration(
        color: active ? AppColors.primary : context.cDivider,
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}

class _LimitPage extends StatelessWidget {
  const _LimitPage({required this.limit, required this.onChanged});
  final int limit;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
      children: [
        Center(
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: const Icon(IconsaxPlusBold.timer_1,
                color: AppColors.primary, size: 32),
          ),
        ),
        const SizedBox(height: 22),
        Text(
          'Set your daily limit',
          textAlign: TextAlign.center,
          style: appFont(
              fontSize: 24, fontWeight: FontWeight.w800, color: context.cText),
        ),
        const SizedBox(height: 8),
        Text(
          'How much screen time do you want to stay under each day? '
          'You can change this anytime.',
          textAlign: TextAlign.center,
          style: appFont(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: context.cTextSec,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 36),
        GoalPicker(minutes: limit, onChanged: onChanged),
      ],
    );
  }
}

/// Asks for notification permission — without it the approaching-limit and
/// over-limit alerts are silently dropped, and the warning event may as well
/// not exist.
class _AlertsPage extends StatelessWidget {
  const _AlertsPage({required this.enabled, required this.onEnable});

  final bool enabled;
  final VoidCallback onEnable;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
      children: [
        Center(
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: AppColors.info.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: Icon(
              enabled
                  ? IconsaxPlusBold.tick_circle
                  : IconsaxPlusBold.notification_bing,
              color: AppColors.info,
              size: 32,
            ),
          ),
        ),
        const SizedBox(height: 22),
        Text(
          enabled ? "You'll get a heads-up" : 'Know before you go over',
          textAlign: TextAlign.center,
          style: appFont(
              fontSize: 24, fontWeight: FontWeight.w800, color: context.cText),
        ),
        const SizedBox(height: 8),
        Text(
          enabled
              ? "We'll tell you half an hour out, and again if you pass your "
                  'limit. Turn it off any time in Settings.'
              : "Undr can tell you when you're half an hour from your limit, "
                  "and when you've passed it. Without alerts you'd only find "
                  'out by opening the app.',
          textAlign: TextAlign.center,
          style: appFont(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: context.cTextSec,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 32),
        if (!enabled)
          ModernButton(label: 'Turn on alerts', onPressed: onEnable),
      ],
    );
  }
}

class _TrackingPage extends StatelessWidget {
  const _TrackingPage({required this.enabled, required this.onEnable});

  final bool enabled;
  final VoidCallback onEnable;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
      children: [
        Center(
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: Icon(
              enabled ? IconsaxPlusBold.tick_circle : IconsaxPlusBold.mobile,
              color: AppColors.accent,
              size: 32,
            ),
          ),
        ),
        const SizedBox(height: 22),
        Text(
          enabled ? "You're all set" : 'Let iOS keep score',
          textAlign: TextAlign.center,
          style: appFont(
              fontSize: 24, fontWeight: FontWeight.w800, color: context.cText),
        ),
        const SizedBox(height: 8),
        Text(
          enabled
              ? 'Your days will log themselves. Change which apps count any '
                  'time in Settings.'
              : 'Pick which apps count toward your limit. iOS tells Undr when '
                  'you go over — it never shares what you were doing.',
          textAlign: TextAlign.center,
          style: appFont(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: context.cTextSec,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 32),
        if (!enabled)
          ModernButton(label: 'Choose apps', onPressed: onEnable),
        if (!enabled) ...[
          const SizedBox(height: 12),
          Text(
            'You can skip this and set it up later. Deleting the app stops '
            "tracking — days it misses won't count.",
            textAlign: TextAlign.center,
            style: appFont(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: context.cTextTer,
            ),
          ),
        ],
      ],
    );
  }
}

class _NamePage extends StatelessWidget {
  const _NamePage({
    required this.first,
    required this.last,
    required this.nickname,
    required this.onChanged,
  });

  final VoidCallback onChanged;

  final TextEditingController first;
  final TextEditingController last;
  final TextEditingController nickname;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
      children: [
        Center(
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: AppColors.info.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: const Icon(IconsaxPlusBold.user,
                color: AppColors.info, size: 32),
          ),
        ),
        const SizedBox(height: 22),
        Text(
          'What should we call you?',
          textAlign: TextAlign.center,
          style: appFont(
              fontSize: 24, fontWeight: FontWeight.w800, color: context.cText),
        ),
        const SizedBox(height: 8),
        Text(
          'This is the name your friends see next to your streak.',
          textAlign: TextAlign.center,
          style: appFont(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: context.cTextSec,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 28),
        _NameField(controller: first, hint: 'First name', onChanged: onChanged),
        const SizedBox(height: 12),
        _NameField(controller: last, hint: 'Last name', onChanged: onChanged),
        const SizedBox(height: 24),
        Text(
          'Widget nickname',
          textAlign: TextAlign.center,
          style: appFont(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: context.cTextSec,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          "Four characters, shown on the home-screen widget where there's "
          "no room for a full name. Skip it and we'll use your initials.",
          textAlign: TextAlign.center,
          style: appFont(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: context.cTextTer,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 12),
        _NameField(controller: nickname, hint: 'e.g. Hern', maxLength: 4),
      ],
    );
  }
}

class _NameField extends StatelessWidget {
  const _NameField({
    required this.controller,
    required this.hint,
    this.maxLength,
    this.onChanged,
  });

  final VoidCallback? onChanged;

  final TextEditingController controller;
  final String hint;
  final int? maxLength;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged == null ? null : (_) => onChanged!(),
      textAlign: TextAlign.center,
      textCapitalization: TextCapitalization.words,
      maxLength: maxLength,
      style: appFont(
          fontSize: 20, fontWeight: FontWeight.w700, color: context.cText),
      decoration: InputDecoration(
        hintText: hint,
        counterText: '',
        hintStyle: appFont(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: context.cTextTer),
        filled: true,
        fillColor: context.cSurface,
        contentPadding: const EdgeInsets.symmetric(vertical: 18),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: context.cDivider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.6),
        ),
      ),
    );
  }
}
