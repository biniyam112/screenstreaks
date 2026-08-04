import 'package:flutter/material.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import '../models/models.dart';
import '../theme.dart';
import 'progress_grid.dart';
import 'usage_gauge.dart';
import 'week_strip.dart';
import 'month_grid.dart';

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
    this.showTodayStatus = true,
    this.onOpenHistory,
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

  /// The today status pill. Off where the daily figure is enough on its own.
  final bool showTodayStatus;

  /// Tapping the month opens the full history.
  final VoidCallback? onOpenHistory;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _HeroCard(
          profile: profile,
          shareButton: shareButton,
          checkInControls: checkInControls,
          showIdentity: showIdentity,
          showLiveUsage: showLiveUsage,
          showTodayStatus: showTodayStatus,
        ),
        const SizedBox(height: 12),
        _SectionCard(
          title: 'This week',
          child: WeekStrip(profile: profile),
        ),
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
        _StatRow(profile: profile),
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
      color = AppColors.primary;
      label = 'Under limit today';
      sub = (record!.usedMinutes != null && !compact)
          ? '${formatDuration(record!.usedMinutes!)} of ${formatDuration(record!.limitMinutes)}'
          : 'Streak alive';
    } else {
      icon = IconsaxPlusBold.close_circle;
      color = AppColors.danger;
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
  const _StatRow({required this.profile});
  final Profile profile;

  @override
  Widget build(BuildContext context) {
    final rate = (profile.successRate(30) * 100).round();
    final items = [
      _Stat(IconsaxPlusBold.flash_1, '${profile.currentStreak}', 'Streak', AppColors.accent),
      _Stat(IconsaxPlusBold.cup, '${profile.longestStreak}', 'Best', AppColors.info),
      _Stat(IconsaxPlusBold.chart_2, '$rate%', '30d', AppColors.primary),
      _Stat(IconsaxPlusBold.tick_circle, '${profile.totalMet}', 'Met', AppColors.primary),
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
