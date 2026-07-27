import 'package:flutter/material.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import '../models/models.dart';
import '../theme.dart';

/// The last 7 days at a glance: a ✓ on days the person stayed under their
/// limit, an ✗ on days they went over, and a muted dash where there's no data.
class WeekStrip extends StatelessWidget {
  const WeekStrip({super.key, required this.profile});

  final Profile profile;

  static const _labels = ['M', 'T', 'W', 'T', 'F', 'S', 'S']; // weekday 1..7

  @override
  Widget build(BuildContext context) {
    final today = dateOnly(DateTime.now());
    final days = List.generate(7, (i) => today.subtract(Duration(days: 6 - i)));

    return Row(
      children: [
        for (var i = 0; i < days.length; i++) ...[
          Expanded(
            child: _DayCell(
              label: _labels[days[i].weekday - 1],
              status: profile.statusOn(days[i]),
              isToday: days[i] == today,
            ),
          ),
          if (i < days.length - 1) const SizedBox(width: 8),
        ],
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.label,
    required this.status,
    required this.isToday,
  });

  final String label;
  final DayStatus status;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    final (Color accent, IconData icon, Color fill) = switch (status) {
      DayStatus.met => (
          AppColors.primary,
          IconsaxPlusBold.tick_circle,
          AppColors.primary.withValues(alpha: 0.16),
        ),
      DayStatus.missed => (
          AppColors.danger,
          IconsaxPlusBold.close_circle,
          AppColors.danger.withValues(alpha: 0.16),
        ),
      DayStatus.none => (
          context.cTextTer,
          IconsaxPlusLinear.minus,
          context.cSurfaceHi,
        ),
    };

    return Column(
      children: [
        Text(
          label,
          style: appFont(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: isToday ? context.cText : context.cTextTer,
          ),
        ),
        const SizedBox(height: 6),
        AspectRatio(
          aspectRatio: 1,
          child: Container(
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(12),
              border: isToday
                  ? Border.all(color: accent, width: 1.6)
                  : null,
            ),
            child: Icon(icon, color: accent, size: 18),
          ),
        ),
      ],
    );
  }
}
