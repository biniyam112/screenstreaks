import 'package:flutter/material.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import '../models/models.dart';
import '../theme.dart';
import 'progress_grid.dart';
import 'usage_gauge.dart';
import 'week_strip.dart';
import 'month_grid.dart';
import 'day_state_card.dart';

/// Reusable profile body used on the home screen and friend detail pages.
///
/// [shareButton]     — shown in the hero header (own profile only).
/// [checkInControls] — ✓ / ✗ buttons in the today row (own profile, iOS only).
/// [footer]          — appended at the end (e.g. friends preview).
class ProfileView extends StatelessWidget {
  const ProfileView({
    super.key,
    required this.profile,
    this.shareButton,
    this.checkInControls,
    this.footer,
    this.showIdentity = true,
    this.showLiveUsage = false,
    this.showProgress = true,
    this.showWeek = true,
    this.showTodayStatus = true,
    this.onOpenHistory,
    this.passesLeft,
    this.monitoring,
    this.onFixMonitoring,
    this.stale = false,
    this.countingSince,
    this.dayState,
    this.onRefreshMonitoring,
    this.onToggleMonitoring,
    this.offSince,
  });

  final Profile profile;
  final Widget? shareButton;
  final Widget? checkInControls;
  final Widget? footer;

  /// Whether the hero shows the avatar + name row. Off on the home screen,
  /// where identity lives in the app bar instead.
  final bool showIdentity;

  /// When true and today's record has exact minutes (Android), the hero shows
  /// a live screen-time gauge instead of the static daily-limit figure.
  final bool showLiveUsage;

  /// The 126-day grid. Off on the home tab so the page fits without scrolling.
  final bool showProgress;

  /// Recovery passes remaining this week. Hidden when null.
  final int? passesLeft;

  /// Whether Screen Time monitoring is live. Hidden when null.
  final bool? monitoring;

  /// Tapping the dot when monitoring is off.
  final VoidCallback? onFixMonitoring;

  /// Monitoring is registered but hasn't reported in days.
  final bool stale;

  /// Where today stands: 0 under, 1 approaching, 2 over.
  final ({int state, DateTime? warnedAt, DateTime? overAt})? dayState;

  /// When the current threshold count began. Later than midnight means
  /// today is only partly measured.
  final DateTime? countingSince;

  /// Re-registering a stale monitor.
  final VoidCallback? onRefreshMonitoring;

  /// Switching tracking on or off deliberately.
  final ValueChanged<bool>? onToggleMonitoring;

  /// How long tracking has been off, when it is. Null while it's running.
  final Duration? offSince;

  /// The seven-day strip. Off on the home tab, where the month calendar
  /// covers the same days and more.
  final bool showWeek;

  /// The today status pill. Off where the daily figure is enough on its own.
  final bool showTodayStatus;


  /// Tapping the month opens the full history.
  final VoidCallback? onOpenHistory;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (stale) ...[
          GestureDetector(
            onTap: onRefreshMonitoring,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  const Icon(IconsaxPlusBold.warning_2,
                      size: 18, color: AppColors.warning),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      "Tracking hasn't reported in a while. Tap to reconnect.",
                      style: appFont(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.warning,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],
        if (monitoring != null) ...[
          _MonitorDot(
            live: monitoring!,
            onTap: onFixMonitoring,
            onToggle: onToggleMonitoring,
            offSince: offSince,
            countingSince: countingSince,
          ),
          const SizedBox(height: 10),
        ],
        _HeroCard(
          profile: profile,
          shareButton: shareButton,
          checkInControls: checkInControls,
          showIdentity: showIdentity,
          showLiveUsage: showLiveUsage,
          showTodayStatus: showTodayStatus,
        ),
        if (showWeek) ...[
          const SizedBox(height: 12),
          _SectionCard(
            title: 'This week',
            child: WeekStrip(profile: profile),
          ),
        ],
        if (showProgress) ...[
          const SizedBox(height: 12),
          _SectionCard(
            title: 'Progress',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ProgressGrid(profile: profile),
                const SizedBox(height: 12),
                const ProgressLegend(),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        if (dayState != null) ...[
          DayStateCard(
            state: dayState!.state,
            limitMinutes: profile.dailyLimitMinutes,
            warnedAt: dayState!.warnedAt,
            overAt: dayState!.overAt,
          ),
          const SizedBox(height: 12),
        ],
        _StatRow(profile: profile, passesLeft: passesLeft),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: onOpenHistory,
          child: _SectionCard(
            title: 'This month',
            child: MonthGrid(profile: profile, month: DateTime.now()),
          ),
        ),
        if (footer != null) ...[const SizedBox(height: 26), footer!],
      ],
    );
  }
}

/// Live indicator — green when Screen Time is watching, red when it isn't.
class _MonitorDot extends StatelessWidget {
  const _MonitorDot({
    required this.live,
    this.onTap,
    this.onToggle,
    this.offSince,
    this.countingSince,
  });

  final bool live;
  final VoidCallback? onTap;
  final ValueChanged<bool>? onToggle;
  final Duration? offSince;
  final DateTime? countingSince;

  /// Counting that began today can't cover the whole day.
  bool get partialToday {
    final s = countingSince;
    if (s == null || !live) return false;
    final now = DateTime.now();
    return s.isAfter(DateTime(now.year, now.month, now.day));
  }

  String get _countingFor {
    final s = countingSince;
    if (s == null) return '';
    final d = DateTime.now().difference(s);
    if (d.inMinutes < 60) return 'tracking ${d.inMinutes}m';
    return 'tracking ${d.inHours}h';
  }

  /// How long the current interval has been registered. Not the same as
  /// usage — iOS never tells us that.
  String get _trackingFor {
    final s = countingSince;
    if (s == null) return 'Tracking';
    final d = DateTime.now().difference(s);
    if (d.inMinutes < 60) return 'tracking ' + d.inMinutes.toString() + 'm';
    return 'tracking ' + d.inHours.toString() + 'h';
  }

  /// Time today that nothing was counted.
  String get _offFor {
    final d = offSince;
    if (d == null) return '0m';
    if (d.inMinutes < 60) return '${d.inMinutes}m';
    if (d.inHours < 24) return '${d.inHours}h';
    return '${d.inDays}d';
  }

  @override
  Widget build(BuildContext context) {
    // Green whenever it's counting, red when it isn't. The "counting Xh"
    // text still says the day is only partly covered.
    final color = live ? context.cGood : context.cBad;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 6, 8, 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: live ? null : onTap,
              child: Text(
                !live
                    ? 'Not tracking'
                    : (countingSince == null ? 'Tracking' : _trackingFor),
                style: appFont(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ),
          ),
          if (offSince != null)
            Text(
              '$_offFor missed today',
              style: appFont(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: context.cTextTer,
              ),
            ),
        ],
      ),
    );
  }
}

/// Plain themed card container.
class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: context.cSurface,
        borderRadius: BorderRadius.circular(22),
      ),
      child: child,
    );
  }
}

/// Card with a titled header row.
class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: appFont(fontSize: 15, fontWeight: FontWeight.w700, color: context.cText),
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Hero — daily limit (big) + how rare it is + today status
// ─────────────────────────────────────────────────────────────────────────────

class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.profile,
    this.shareButton,
    this.checkInControls,
    this.showIdentity = true,
    this.showLiveUsage = false,
    this.showTodayStatus = true,
  });

  final Profile profile;
  final Widget? shareButton;
  final Widget? checkInControls;
  final bool showIdentity;
  final bool showLiveUsage;
  final bool showTodayStatus;

  @override
  Widget build(BuildContext context) {
    final avatarColor = profile.avatarColor ?? AppColors.primary;
    final today = dateOnly(DateTime.now());
    final record = profile.byDay[today];

    // Android: when we know today's exact minutes, show the live gauge.
    final useGauge = showLiveUsage && record?.usedMinutes != null;

    return _Card(
      child: Column(
        children: [
          if (showIdentity) ...[
            Row(
              children: [
                _Avatar(initials: profile.initials, color: avatarColor),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    profile.displayName,
                    style: appFont(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        color: context.cText),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (shareButton != null) shareButton!,
              ],
            ),
            const SizedBox(height: 22),
          ] else
            const SizedBox(height: 4),
          if (useGauge)
            UsageGauge(
              usedMinutes: record!.usedMinutes!,
              limitMinutes: record.limitMinutes,
            )
          else
            _LimitFigure(limitMinutes: profile.dailyLimitMinutes),
          if (showTodayStatus) ...[
          const SizedBox(height: 20),
          _TodayStatus(
            record: record,
            checkInControls: checkInControls,
            // The gauge already shows used/limit, so keep the pill's messaging
            // but suppress the duplicate minutes line.
            compact: useGauge,
          ),
          ],
        ],
      ),
    );
  }
}

/// Static "DAILY LIMIT" figure with the community-rarity caption (iOS / friends
/// / before any usage is known).
class _LimitFigure extends StatelessWidget {
  const _LimitFigure({required this.limitMinutes});
  final int limitMinutes;

  @override
  Widget build(BuildContext context) {
    final pct = (communityUnderRate(limitMinutes) * 100).round();
    final prefix = pct < 50 ? 'Only ' : '';
    return Column(
      children: [
        Text(
          'DAILY LIMIT',
          style: appFont(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.6,
            color: context.cTextSec,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          formatDuration(limitMinutes),
          style: appFont(
            fontSize: 58,
            fontWeight: FontWeight.w800,
            height: 1,
            letterSpacing: -2,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          '$prefix$pct% of people stay under this a day',
          textAlign: TextAlign.center,
          style: appFont(
              fontSize: 13, fontWeight: FontWeight.w500, color: context.cTextSec),
        ),
      ],
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.initials, required this.color});
  final String initials;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(color: color.withValues(alpha: 0.16), shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: appFont(fontWeight: FontWeight.w700, fontSize: 14, color: color),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Today status pill
// ─────────────────────────────────────────────────────────────────────────────

class _TodayStatus extends StatelessWidget {
  const _TodayStatus({
    required this.record,
    this.checkInControls,
    this.compact = false,
  });
  final DailyRecord? record;
  final Widget? checkInControls;

  /// When true, the used/limit minutes line is dropped (the gauge shows it).
  final bool compact;

  @override
  Widget build(BuildContext context) {
    IconData icon;
    Color color;
    String label, sub;

    if (record == null) {
      if (checkInControls == null) return const SizedBox.shrink();
      icon = IconsaxPlusBold.clock;
      color = context.cTextSec;
      label = 'Not logged yet';
      sub = 'Did you stay under today?';
    } else if (record!.limitMet) {
      icon = IconsaxPlusBold.tick_circle;
      color = context.cGood;
      label = 'Under limit today';
      sub = (record!.usedMinutes != null && !compact)
          ? '${formatDuration(record!.usedMinutes!)} of ${formatDuration(record!.limitMinutes)}'
          : 'Streak alive';
    } else {
      icon = IconsaxPlusBold.close_circle;
      color = context.cBad;
      label = 'Over limit today';
      sub = (record!.usedMinutes != null && !compact)
          ? '${formatDuration(record!.usedMinutes!)} of ${formatDuration(record!.limitMinutes)}'
          : 'Fresh start tomorrow';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(color: context.cSurfaceHi, borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: appFont(fontWeight: FontWeight.w700, fontSize: 13.5, color: context.cText),
                ),
                Text(
                  sub,
                  style: appFont(
                    fontSize: 12,
                    color: context.cTextSec,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          if (checkInControls != null) ...[const SizedBox(width: 8), checkInControls!],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Stat row
// ─────────────────────────────────────────────────────────────────────────────

class _StatRow extends StatelessWidget {
  const _StatRow({required this.profile, this.passesLeft});
  final Profile profile;
  final int? passesLeft;

  @override
  Widget build(BuildContext context) {
    final rate = (profile.successRate(30) * 100).round();
    final items = [
      _Stat(IconsaxPlusBold.flash_1, '${profile.currentStreak}', 'Streak', context.cWarn),
      _Stat(IconsaxPlusBold.cup, '${profile.longestStreak}', 'Best', AppColors.info),
      _Stat(IconsaxPlusBold.chart_2, '$rate%', '30d', context.cGood),
      if (passesLeft != null)
        _Stat(
            IconsaxPlusBold.shield_tick,
            '$passesLeft',
            passesLeft! < 0 ? 'Owed' : 'Passes',
            passesLeft! < 0 ? context.cBad : context.cWarn)
      else
        _Stat(IconsaxPlusBold.tick_circle, '${profile.totalMet}', 'Met',
            AppColors.primary),
    ];
    return Row(
      children: [
        for (int i = 0; i < items.length; i++) ...[
          Expanded(child: _StatTile(stat: items[i])),
          if (i < items.length - 1) const SizedBox(width: 10),
        ],
      ],
    );
  }
}

class _Stat {
  const _Stat(this.icon, this.value, this.label, this.color);
  final IconData icon;
  final String value, label;
  final Color color;
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.stat});
  final _Stat stat;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: BoxDecoration(
        color: context.cSurface,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(stat.icon, size: 18, color: stat.color),
          const SizedBox(height: 8),
          Text(
            stat.value,
            style: appFont(
              fontSize: 19,
              fontWeight: FontWeight.w800,
              color: context.cText,
              height: 1,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            stat.label,
            style: appFont(fontSize: 11, fontWeight: FontWeight.w500, color: context.cTextTer),
          ),
        ],
      ),
    );
  }
}
