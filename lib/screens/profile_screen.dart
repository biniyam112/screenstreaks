import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:share_plus/share_plus.dart';

import '../app_events.dart';
import '../data/repo_scope.dart';
import '../data/repository.dart';
import '../models/models.dart';
import '../services/home_widget_service.dart';
import '../services/prefs.dart';
import '../services/usage_service.dart';
import '../theme.dart';
import '../widgets.dart';
import '../widgets/profile_view.dart';
import 'friend_detail_screen.dart';
import '../services/screen_time.dart';
import 'history_screen.dart';
import '../widgets/aurora_header.dart';
import '../widgets/avatar.dart';
import '../widgets/name_prompt.dart';
import '../services/notifications.dart';
import 'needs_you_screen.dart';
import '../services/widget_push.dart';
import '../widgets/app_background.dart';

/// The user's home page: streak, weekly chart, today check-in, share, friends.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, this.onSeeFriends, this.onProfile});

  final VoidCallback? onSeeFriends;
  final VoidCallback? onProfile;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> with WidgetsBindingObserver {
  StreamSubscription<void>? _records;
  Profile? _me;
  List<Profile> _friends = [];
  bool _loading = true;
  bool _monitoring = false;
  int _passesLeft = 1;
  Duration? _offSince;
  bool _stale = false;
  bool _askedToResume = false;
  bool _askedAboutSleep = false;
  int _needsYou = 0;
  DateTime? _countingSince;
  ({int state, DateTime? warnedAt, DateTime? overAt}) _dayState =
      (state: 0, warnedAt: null, overAt: null);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _records = RepoScope.of(context).recordChanges().listen((_) {
        if (mounted) _load();
      });
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _records = RepoScope.of(context).recordChanges().listen((_) {
        if (mounted) _load();
      });
    });
    // Refresh when the profile changes elsewhere (e.g. daily limit saved in
    // Settings), since this tab stays alive in the IndexedStack.
    profileRevision.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _records?.cancel();
    _records?.cancel();
    profileRevision.removeListener(_load);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
    // Leaving the app is when we know what's still stuck on this phone.
    if (state == AppLifecycleState.paused) {
      Notifications.init().then((_) => Notifications.scheduleUnsyncedNudge());
    }
  }

  Future<void> _load() async {
    final repo = RepoScope.of(context);
    await _autoCheckInAndroid(repo);
    await _drainScreenTime(repo);
    try {
      final me = await repo.me();
      final friends = await repo.friends();
      // A different account signing in inherits whatever was counting —
      // against the previous person's limit and apps. Start over.
      final owner = await Prefs.monitorOwner();
      if (owner != null && owner != me.id) {
        await ScreenTime.stopMonitoring();
        await Prefs.setTrackingEnabled(false);
      }
      if (owner != me.id) await Prefs.setMonitorOwner(me.id);

      var savedGoal = await Prefs.goalMinutes();
      // A limit change made yesterday takes effect now — the new day's count
      // starts from zero anyway, so nothing is lost by switching here.
      final pending = await Prefs.pendingGoal();
      final queuedOn = await Prefs.pendingGoalSetOn();
      if (pending != null && pending != savedGoal) {
        final now0 = DateTime.now();
        final today0 = DateTime(now0.year, now0.month, now0.day);
        // Applies only once the day has actually turned over.
        // The extension may already have applied it at midnight — in which
        // case activeLimit is the new value and we just catch up.
        final activeNow = await ScreenTime.activeLimit();
        if (activeNow == pending ||
            (queuedOn != null && today0.isAfter(queuedOn))) {
          // Clear the pending value only once the change has actually
          // landed — otherwise a failed write loses it silently.
          await repo.setDailyLimit(pending);
          await Prefs.setGoalMinutes(pending);
          await Prefs.setPendingGoal(null);
          savedGoal = pending;
        }
      }
      // One personal pass a week.
      final spent = await repo.spentPasses();
      final weekAgo = startOfWeek();
      final usedThisWeek = spent
          .where((p) => p.groupId == null && p.day.isAfter(weekAgo))
          .length;
      // A group pass spent when the personal one was already gone borrows
      // from next week — shown as -1 until that week comes round.
      final owed = spent
          .where((p) => p.kind == 'group_debt' && p.day.isAfter(weekAgo))
          .length;
      final monitoring = await _ensureMonitoring(savedGoal);
      // A monitor that's registered but hasn't woken in days isn't watching
      // anything — the interval callbacks alone should fire daily.
      final stale = await ScreenTime.looksStale();
      // Counting restarts whenever the monitor is re-registered, so a start
      // time later than midnight means today is only partly measured.
      final countingSince = await ScreenTime.monitoringSince();
      final dayState = await ScreenTime.dayState();
      // Publish what we're watching so friends can see thin coverage.
      if (ScreenTime.supported) {
        final counts = await ScreenTime.selectionCount();
        if (counts.apps != me.trackedApps ||
            counts.categories != me.trackedCategories) {
          await repo.setTrackedCounts(counts.apps, counts.categories);
        }
      }
      // Anything waiting on the user, counted for the bell.
      var needsYou = 0;
      try {
        needsYou = (await repo.pendingInvites()).length +
            (await repo.pendingProposals()).length;
      } catch (_) {
        // The badge is cosmetic; never let it break the load.
      }
      // Keep the session log honest: open one when tracking is live, close it
      // when we find it stopped without being told.
      final sessions = await repo.monitoringSessions();
      final open = sessions.where((x) => x.endedAt == null).toList();
      if (monitoring && open.isEmpty) {
        await repo.logMonitoringOn();
      } else if (!monitoring && open.isNotEmpty) {
        await repo.logMonitoringOff('detected');
      }
      // Time today that nothing was counted: since midnight, minus what
      // the current count covers. Restarting mid-morning means every hour
      // before it is missed, because the threshold count began from zero.
      final now = DateTime.now();
      final midnight = DateTime(now.year, now.month, now.day);
      final countStart = countingSince != null && countingSince.isAfter(midnight)
          ? countingSince
          : midnight;
      final counted = monitoring ? now.difference(countStart) : Duration.zero;
      final elapsed = now.difference(midnight);
      final offSince = counted >= elapsed ? Duration.zero : elapsed - counted;
      if (!mounted) return;
      setState(() {
        _monitoring = monitoring;
        _passesLeft = (1 - usedThisWeek - owed).clamp(-1, 1);
        _offSince = offSince;
        _stale = stale;
        _countingSince = countingSince;
        _dayState = dayState;
        _needsYou = needsYou;
        _me = me.dailyLimitMinutes == savedGoal
            ? me
            : me.copyWith(dailyLimitMinutes: savedGoal);
        _friends = friends;
        _loading = false;
      });
      // Keep the home-screen widget in sync with the latest week/streak.
      HomeWidgetService.update(me);
      // Keeps the widget's limits current without waiting for a visit to
      // the Social tab.
      if (mounted) WidgetPush.push(repo, meProfile: me);

      // Accounts made before these fields existed have no first name — ask
      // once so lists and the widget have something to show.
      if (mounted) await _offerToResume();
      if (mounted) await _offerSleepPass(repo, me);

      if (mounted && (me.firstName ?? '').trim().isEmpty) {
        await showNamePrompt(context, me);
        if (mounted) _load();
      }
    } catch (_) {
      // Only reachable on a first-ever launch with no connection and no cache;
      // otherwise the offline layer serves cached data. Show a retry instead
      // of an endless spinner.
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  /// Keeps the monitor watching the current goal — restarts it when the
  /// limit changed or monitoring was never started. Returns whether it's on.
  Future<bool> _ensureMonitoring(int goalMinutes) async {
    if (!ScreenTime.supported) return false;
    // Respect a deliberate stop — otherwise this restarts monitoring the
    // moment the user switches it off.
    if (!await Prefs.trackingEnabled()) return false;
    try {
      // An install wipes the app-group container, so a missing selection
      // doesn't mean the user opted out — Prefs remembers that they didn't.
      if (!await ScreenTime.hasSelection()) {
        if (await Prefs.trackingEnabled() && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Tracking stopped — set it up again in Settings'),
              duration: Duration(seconds: 6),
            ),
          );
        }
        return false;
      }
      final active = await ScreenTime.activeLimit();
      if (active == goalMinutes) return true;

      // Don't hammer it. If a restart doesn't take — which has happened —
      // retrying on every screen load produces a burst of registrations and
      // can fire the threshold spuriously.
      final lastTry = await Prefs.lastMonitorRestart();
      if (lastTry != null &&
          DateTime.now().difference(lastTry) < const Duration(minutes: 10)) {
        return active > 0;
      }
      await Prefs.setLastMonitorRestart(DateTime.now());
      // Covers a fresh install too: the selection is restored above, so this
      // silently puts monitoring back rather than waiting for a manual tap.
      return await ScreenTime.startMonitoring(goalMinutes);
    } catch (_) {
      return false;
    }
  }

  /// Turns outcomes recorded by the iOS monitor extension into check-ins.
  /// Safe to re-run — checkIn replaces any record for the same day.
  Future<void> _drainScreenTime(Repository repo) async {
    if (!ScreenTime.supported) return;
    try {
      final pending = await ScreenTime.pendingOutcomes();
      if (pending.isEmpty) return;
      final limit = await Prefs.goalMinutes();
      final consumed = <String>[];
      for (final entry in pending.entries) {
        final day = ScreenTime.parseDay(entry.key);
        if (day == null) continue;
        await repo.checkIn(
          day: day,
          limitMet: entry.value,
          limitMinutes: limit,
          source: 'auto',
        );
        consumed.add(entry.key);
      }
      await ScreenTime.clearPending(consumed);

      // Days monitoring only partly covered: recorded so the user sees the
      // app working, but they count neither way.
      final partials = await ScreenTime.partialDays();
      final donePartials = <String>[];
      for (final key in partials) {
        final day = ScreenTime.parseDay(key);
        if (day == null) continue;
        await repo.checkIn(
          day: day,
          limitMet: false,
          limitMinutes: limit,
          source: 'auto',
          partial: true,
        );
        donePartials.add(key);
      }
      await ScreenTime.clearPartials(donePartials);

      // The rule: if counting doesn't cover the whole day, the day can't be
      // judged. Grey it now rather than letting 23:59 record a pass we can't
      // justify. A day already lost stays lost.
      final startedAt = await ScreenTime.monitoringSince();
      if (startedAt != null) {
        final now = DateTime.now();
        final midnight = DateTime(now.year, now.month, now.day);
        if (startedAt.isAfter(midnight)) {
          final me = await repo.me();
          final existing = me.byDay[dateOnly(now)];
          if (existing == null || existing.limitMet) {
            await repo.checkIn(
              day: now,
              limitMet: false,
              limitMinutes: limit,
              source: 'auto',
              partial: true,
            );
          }
        }
      }
      await _fillUnmonitoredGaps(repo, limit);
    } catch (e) {
      // Never let a drain failure block loading — but leave a trace, or a
      // week of failed uploads looks identical to nothing happening.
      debugPrint('DRAIN FAILED: $e');
      await ScreenTime.log('drain failed: $e');
    }
  }

  /// A threshold crossed between 2 and 5am is almost certainly a screen
  /// left on overnight. Offer the sleep pass — separate from the weekly one,
  /// and only if they haven't used it.
  Future<void> _offerSleepPass(Repository repo, Profile me) async {
    if (_askedAboutSleep || !ScreenTime.supported) return;
    _askedAboutSleep = true;

    // The overnight watcher flags a day directly — an hour of use between
    // 2 and 5am — rather than us guessing from when the limit was crossed.
    final flagged = await ScreenTime.sleepFlags();
    if (flagged.isEmpty) return;

    final spent = await repo.spentPasses();
    final weekAgo = DateTime.now().subtract(const Duration(days: 7));
    final usedSleep = spent.any(
        (p) => p.kind == 'sleep' && p.day.isAfter(weekAgo));
    if (usedSleep) return;

    // Most recent qualifying miss that hasn't already been recovered.
    final claimed = spent.map((p) => dateOnly(p.day)).toSet();
    DateTime? candidate;
    for (final key in flagged) {
      final day = ScreenTime.parseDay(key);
      if (day == null || claimed.contains(dateOnly(day))) continue;
      final record = me.byDay[dateOnly(day)];
      if (record == null || record.limitMet || record.partial) continue;
      if (candidate == null || day.isAfter(candidate)) candidate = day;
    }
    if (candidate == null || !mounted) return;


    final claim = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: c.cSheet,
        title: Text('Screen left on?',
            style: appFont(fontWeight: FontWeight.w700, color: c.cText)),
        content: Text(
          'Your phone was in use for over an hour between 2 and 5am, which '
          'usually means a video kept playing or the screen never locked. '
          'Claim your sleep pass to '
          "recover that day — one a week, separate from your normal pass.",
          style: appFont(fontWeight: FontWeight.w500, color: c.cTextSec),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text('It was me',
                style: appFont(
                    color: c.cTextSec, fontWeight: FontWeight.w600)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text('Claim it',
                style: appFont(
                    color: AppColors.primary, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (claim != true) return;

    try {
      await repo.spendPass(candidate, kind: 'sleep');
      if (mounted) _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  /// After a sign-in that left tracking off — a different account, or a
  /// deliberate stop — offer to start it rather than silently not counting.
  Future<void> _offerToResume() async {
    if (_askedToResume || !ScreenTime.supported) return;
    if (await Prefs.trackingEnabled()) return;
    if (!mounted) return;
    _askedToResume = true;

    final start = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: c.cSheet,
        title: Text('Start tracking?',
            style: appFont(fontWeight: FontWeight.w700, color: c.cText)),
        content: Text(
          "Nothing's being counted right now, so today won't be judged either "
          'way. Turn it on to start.',
          style: appFont(fontWeight: FontWeight.w500, color: c.cTextSec),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text('Not now',
                style: appFont(
                    color: c.cTextSec, fontWeight: FontWeight.w600)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text('Start tracking',
                style: appFont(
                    color: AppColors.primary, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (start != true) return;

    await ScreenTime.requestAuthorization();
    if (!await ScreenTime.hasSelection()) await ScreenTime.pickApps();
    final ok = await ScreenTime.startMonitoring(await Prefs.goalMinutes());
    if (ok) await Prefs.setTrackingEnabled(true);
    if (mounted) _load();
  }

  /// Re-register the monitor with the selection we already have. Fixes a
  /// stale registration without making the user pick apps again.
  Future<void> _refreshMonitoring() async {
    await ScreenTime.startMonitoring(await Prefs.goalMinutes());
    if (mounted) _load();
  }

  /// Deliberately switching tracking on or off. Off needs confirming — days
  /// it misses can't be judged, and the streak suffers for it.
  Future<void> _toggleMonitoring(bool on) async {
    final repo = RepoScope.of(context);
    if (on) {
      await ScreenTime.requestAuthorization();
      if (!await ScreenTime.hasSelection()) await ScreenTime.pickApps();
      final ok = await ScreenTime.startMonitoring(await Prefs.goalMinutes());
      if (ok) {
        await Prefs.setTrackingEnabled(true);
        await repo.logMonitoringOn();
      }
      if (mounted) _load();
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: c.cSheet,
        title: Text('Stop tracking?',
            style: appFont(fontWeight: FontWeight.w700, color: c.cText)),
        content: Text(
          "Days while it's off can't be judged — they won't count toward your "
          'streak, and your group will see the gap.',
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
    if (confirmed != true) return;

    await ScreenTime.stopMonitoring();
    await Prefs.setTrackingEnabled(false);
    await repo.logMonitoringOff('manual');
    // Today can't be judged once we stop watching it — grey, not a miss.
    await repo.checkIn(
      day: DateTime.now(),
      limitMet: false,
      limitMinutes: await Prefs.goalMinutes(),
      source: 'manual',
      partial: true,
    );
    if (mounted) _load();
  }

  /// Marks past days that have no record at all. Nothing runs while the app
  /// is closed, so a stretch where monitoring was off leaves gaps — recorded
  /// as unjudged rather than left blank, which would look like a day still in
  /// progress.
  Future<void> _fillUnmonitoredGaps(Repository repo, int limit) async {
    if (!ScreenTime.supported) return;
    try {
      final me = await repo.me();
      final logged = me.byDay;
      final today = dateOnly(DateTime.now());
      if (me.records.isEmpty) return;
      // Never fill before the first day we have any record for — those days
      // predate the account rather than representing a monitoring gap.
      final firstDay = me.records
          .map((r) => dateOnly(r.day))
          .reduce((a, b) => a.isBefore(b) ? a : b);
      // Only look back a week; older gaps aren't worth chasing.
      for (var i = 1; i <= 7; i++) {
        final day = today.subtract(Duration(days: i));
        if (day.isBefore(firstDay)) continue;
        if (logged.containsKey(day)) continue;
        await repo.checkIn(
          day: day,
          limitMet: false,
          limitMinutes: limit,
          source: 'auto',
          partial: true,
        );
      }
    } catch (_) {
      // Best effort; retried next launch.
    }
  }

  /// Reads today's usage and records it. Uses the locally-stored goal (kept in
  /// sync by Settings) so it needs no network, and checkIn is local-first — so
  /// this is safe and lossless even fully offline.
  Future<void> _autoCheckInAndroid(Repository repo) async {
    if (!Platform.isAndroid) return;
    try {
      if (!await UsageService.hasPermission()) return;
      final limit = await Prefs.goalMinutes();
      final used = await UsageService.todayMinutes();
      await repo.checkIn(
        day: DateTime.now(),
        limitMet: used <= limit,
        usedMinutes: used,
        limitMinutes: limit,
        source: 'auto',
      );
    } catch (_) {
      // Never let a check-in failure block loading.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Transparent so the gradient shows rather than the scaffold colour.
      backgroundColor: Colors.transparent,
      body: AppBackground(
        child: Column(
        children: [
          AuroraHeader(
            title: 'Your streak',
            tint: const Color(0xFF9B7FE8),
            trailing: _me == null
                ? null
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GestureDetector(
                        onTap: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const NeedsYouScreen(),
                            ),
                          );
                          if (mounted) _load();
                        },
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Container(
                              width: 34,
                              height: 34,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: context.cSurface,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(IconsaxPlusLinear.notification,
                                  size: 17, color: context.cTextSec),
                            ),
                            if (_needsYou > 0)
                              Positioned(
                                top: -1,
                                right: -1,
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: const BoxDecoration(
                                    color: AppColors.danger,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Text(
                                    _needsYou.toString(),
                                    style: appFont(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      GestureDetector(
                        onTap: widget.onProfile,
                        child: Avatar(profile: _me!, size: 34),
                      ),
                    ],
                  ),
          ),
          Expanded(
            child: SafeArea(
              top: false,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _me == null
            ? _LoadError(
                onRetry: () {
                  setState(() => _loading = true);
                  _load();
                },
              )
            : RefreshIndicator(
                color: AppColors.primary,
                onRefresh: _load,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 32),
                  child: ProfileView(
                    profile: _me!,
                    showIdentity: false,
                    showLiveUsage: Platform.isAndroid,
                    showProgress: false,
                    showWeek: false,
                    passesLeft: _passesLeft,
                    monitoring: ScreenTime.supported ? _monitoring : null,
                    stale: _stale,
                    countingSince: _countingSince,
                    dayState: _dayState,
                    onRefreshMonitoring: _refreshMonitoring,
                    offSince: _offSince,
                    onFixMonitoring: () async {
                      await ScreenTime.requestAuthorization();
                      if (!await ScreenTime.hasSelection()) {
                        await ScreenTime.pickApps();
                      }
                      await ScreenTime.startMonitoring(
                          await Prefs.goalMinutes());
                      if (mounted) _load();
                    },
                    onOpenHistory: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => HistoryScreen(profile: _me!),
                      ),
                    ),
                    showTodayStatus: false,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      ),
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(IconsaxPlusLinear.cloud_cross, size: 44, color: context.cTextTer),
            const SizedBox(height: 16),
            Text(
              "Can't reach Undr",
              style: appFont(fontSize: 17, fontWeight: FontWeight.w800, color: context.cText),
            ),
            const SizedBox(height: 6),
            Text(
              'Check your connection and try again.',
              textAlign: TextAlign.center,
              style: appFont(fontSize: 13.5, fontWeight: FontWeight.w500, color: context.cTextSec),
            ),
            const SizedBox(height: 20),
            ModernButton(
              label: 'Retry',
              icon: IconsaxPlusLinear.refresh,
              expand: false,
              onPressed: onRetry,
            ),
          ],
        ),
      ),
    );
  }
}

class _CheckInButtons extends StatelessWidget {
  const _CheckInButtons({required this.profile, required this.onChanged});
  final Profile profile;
  final VoidCallback onChanged;

  Future<void> _log(BuildContext context, bool met) async {
    final repo = RepoScope.of(context);
    await repo.checkIn(
      day: DateTime.now(),
      limitMet: met,
      limitMinutes: profile.dailyLimitMinutes,
      source: 'manual',
    );
    HapticFeedback.selectionClick();
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _RoundAction(
          icon: IconsaxPlusLinear.close_square,
          color: AppColors.danger,
          onTap: () => _log(context, false),
        ),
        const SizedBox(width: 8),
        _RoundAction(
          icon: IconsaxPlusLinear.tick_square,
          color: AppColors.primary,
          onTap: () => _log(context, true),
        ),
      ],
    );
  }
}

class _RoundAction extends StatelessWidget {
  const _RoundAction({required this.icon, required this.color, required this.onTap});
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: color, size: 22),
      ),
    );
  }
}

class _FriendsPreview extends StatelessWidget {
  const _FriendsPreview({required this.friends, this.onSeeAll});
  final List<Profile> friends;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Friends',
              style: appFont(fontSize: 17, fontWeight: FontWeight.w700, color: context.cText),
            ),
            const Spacer(),
            if (onSeeAll != null && friends.isNotEmpty)
              TextButton(
                onPressed: onSeeAll,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 0),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('See all'),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (friends.isEmpty)
          _EmptyFriends(onShare: onSeeAll)
        else
          ...friends
              .take(3)
              .map(
                (f) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: FriendRow(friend: f),
                ),
              ),
      ],
    );
  }
}

class _EmptyFriends extends StatelessWidget {
  const _EmptyFriends({this.onShare});
  final VoidCallback? onShare;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 18),
      decoration: BoxDecoration(
        color: context.cSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: context.cDivider),
      ),
      child: Column(
        children: [
          Icon(IconsaxPlusBold.profile_2user, size: 30, color: context.cTextTer),
          const SizedBox(height: 10),
          Text(
            'No friends yet',
            style: appFont(fontWeight: FontWeight.w700, fontSize: 15, color: context.cText),
          ),
          const SizedBox(height: 4),
          Text(
            'Share your code to keep each other accountable.',
            textAlign: TextAlign.center,
            style: appFont(fontSize: 13, color: context.cTextSec, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}

/// Compact friend row with avatar, streak, and today's status chip.
class FriendRow extends StatelessWidget {
  const FriendRow({super.key, required this.friend});
  final Profile friend;

  @override
  Widget build(BuildContext context) {
    final todayStatus = friend.statusOn(DateTime.now());
    final streak = friend.currentStreak;

    return Material(
      color: context.cSurface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => FriendDetailScreen(friendId: friend.id))),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: context.cDivider),
          ),
          child: Row(
            children: [
              Avatar(profile: friend, size: 42),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      friend.listName,
                      style: appFont(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: context.cText,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(
                          streak == 0 ? IconsaxPlusBold.moon : IconsaxPlusBold.flash_1,
                          size: 13,
                          color: streak == 0 ? context.cTextTer : AppColors.accent,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          streak == 0 ? 'No streak' : '$streak day streak',
                          style: appFont(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                            color: context.cTextSec,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              _StatusDot(status: todayStatus),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.status});
  final DayStatus status;

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (status) {
      DayStatus.met => (AppColors.primary, 'Under'),
      DayStatus.missed => (AppColors.danger, 'Over'),
      DayStatus.none => (context.cTextTer, 'No log'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: appFont(fontSize: 12, fontWeight: FontWeight.w700, color: color),
      ),
    );
  }
}

/// Bottom sheet to share your invite link / code.
void showShareSheet(BuildContext context, Profile me) {
  final repo = RepoScope.of(context);
  final link = repo.shareLink(me.shareCode);
  final inviteMessage =
      "Let's keep each other under our screen-time limit on Undr 👀\n\n"
      'Connect with me: $link\n\n'
      'Or enter my code in the app: ${me.shareCode}';
  showModalBottomSheet(
    context: context,
    backgroundColor: context.cBg,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (sheetContext) => Padding(
      padding: const EdgeInsets.fromLTRB(22, 12, 22, 30),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: sheetContext.cDivider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 22),
          Text(
            'Invite a friend',
            style: appFont(fontSize: 20, fontWeight: FontWeight.w800, color: sheetContext.cText),
          ),
          const SizedBox(height: 6),
          Text(
            'Share your code. When they enter it in Undr, '
            "you'll see each other's streaks.",
            style: appFont(
              fontSize: 13.5,
              color: sheetContext.cTextSec,
              fontWeight: FontWeight.w500,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 22),
          // High-contrast code chip.
          Container(
            padding: const EdgeInsets.symmetric(vertical: 22),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
            ),
            child: Center(
              child: Text(
                me.shareCode,
                style: appMono(
                  fontSize: 34,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 8,
                  color: AppColors.primary,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Primary action: fire the OS share sheet straight into WhatsApp,
          // Messages, etc. with the link + code pre-written.
          ModernButton(
            label: 'Share invite',
            icon: IconsaxPlusBold.send_2,
            onPressed: () async {
              // Capture the anchor rect before awaiting (needed for the iPad
              // popover); keep the sheet open so the anchor stays valid.
              final box = sheetContext.findRenderObject() as RenderBox?;
              final origin = box != null ? box.localToGlobal(Offset.zero) & box.size : null;
              await SharePlus.instance.share(
                ShareParams(
                  text: inviteMessage,
                  subject: 'Join me on Undr',
                  sharePositionOrigin: origin,
                ),
              );
            },
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: ModernButton(
                  label: 'Copy link',
                  icon: IconsaxPlusLinear.link_1,
                  outlined: true,
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: link));
                    Navigator.pop(sheetContext);
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(const SnackBar(content: Text('Invite link copied')));
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ModernButton(
                  label: 'Copy code',
                  icon: IconsaxPlusBold.copy,
                  outlined: true,
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: me.shareCode));
                    Navigator.pop(sheetContext);
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(const SnackBar(content: Text('Code copied')));
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
