import 'package:flutter/material.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import '../models/models.dart';
import '../theme.dart';

/// Two smooth vertical bars comparing you and a friend, day by day.
///
/// Each bar is a vertical slice per day (newest at the top). Days under the
/// limit are green, days over are red, and — because the colours are laid down
/// as an interpolating gradient — the transitions melt into each other with no
/// hard border. It reads as two glowing "activity spines".
class StreakCompare extends StatelessWidget {
  const StreakCompare({
    super.key,
    required this.me,
    required this.friend,
    this.days = 30,
    this.height = 240,
  });

  final Profile me;
  final Profile friend;
  final int days;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _Spine(
            profile: me,
            days: days,
            height: height,
            label: 'You',
            color: me.avatarColor ?? AppColors.primary,
          ),
        ),
        const SizedBox(width: 18),
        Expanded(
          child: _Spine(
            profile: friend,
            days: days,
            height: height,
            label: friend.displayName,
            color: friend.avatarColor ?? AppColors.info,
          ),
        ),
      ],
    );
  }
}

class _Spine extends StatelessWidget {
  const _Spine({
    required this.profile,
    required this.days,
    required this.height,
    required this.label,
    required this.color,
  });

  final Profile profile;
  final int days;
  final double height;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final today = dateOnly(DateTime.now());
    // One solid slice per day, newest at the top. Hard edges — each day's
    // colour stays crisp and never blends into the neighbouring days.
    final colors = <Color>[
      for (var i = 0; i < days; i++)
        _colorFor(context, profile.statusOn(today.subtract(Duration(days: i)))),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            height: height,
            width: double.infinity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final c in colors)
                  Expanded(child: ColoredBox(color: c)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: appFont(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: context.cText,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Icon(
              profile.currentStreak == 0
                  ? IconsaxPlusBold.moon
                  : IconsaxPlusBold.flash_1,
              size: 13,
              color: profile.currentStreak == 0
                  ? context.cTextTer
                  : AppColors.accent,
            ),
            const SizedBox(width: 4),
            Text(
              profile.currentStreak == 0
                  ? 'No streak'
                  : '${profile.currentStreak} day streak',
              style: appFont(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: context.cTextSec,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Color _colorFor(BuildContext context, DayStatus status) => switch (status) {
        DayStatus.met => AppColors.primary,
        DayStatus.missed => AppColors.danger,
        DayStatus.none => context.cSurfaceHi,
      };
}
