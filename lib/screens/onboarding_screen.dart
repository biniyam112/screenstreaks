import 'package:flutter/material.dart';
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
  final _nameController = TextEditingController();

  int _page = 0;
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
    _nameController.dispose();
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
        _nameController.text =
            me.displayName == 'Friend' ? '' : me.displayName;
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
  Future<void> _enableTracking() async {
    final ok = await ScreenTime.requestAuthorization();
    if (!ok || !mounted) return;
    await ScreenTime.pickApps();
    if (!mounted) return;
    final started = await ScreenTime.startMonitoring(_limit);
    if (mounted) setState(() => _tracking = started);
  }

  Future<void> _finish() async {
    final name = _nameController.text.trim();
    setState(() => _saving = true);
    final repo = RepoScope.of(context);
    try {
      await repo.setDailyLimit(_limit);
      await Prefs.setGoalMinutes(_limit);
      if (name.isNotEmpty) await repo.setDisplayName(name);
      await Prefs.setOnboarded(true);
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
                  _NamePage(controller: _nameController),
                  if (ScreenTime.supported)
                    _TrackingPage(
                      enabled: _tracking,
                      onEnable: _enableTracking,
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              child: _page < (ScreenTime.supported ? 2 : 1)
                  ? ModernButton(
                      label: 'Continue',
                      icon: IconsaxPlusBold.arrow_right_3,
                      onPressed: _next,
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
            'You can skip this and set it up later.',
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
  const _NamePage({required this.controller});
  final TextEditingController controller;

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
        const SizedBox(height: 32),
        TextField(
          controller: controller,
          textAlign: TextAlign.center,
          textCapitalization: TextCapitalization.words,
          style: appFont(
              fontSize: 20, fontWeight: FontWeight.w700, color: context.cText),
          decoration: InputDecoration(
            hintText: 'Your name',
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
        ),
      ],
    );
  }
}
