import 'package:flutter/material.dart';

import '../models/models.dart';
import '../theme.dart';

/// A GitHub-style contribution grid of the user's whole history.
///
/// Columns are weeks (oldest → current on the right), rows are weekdays
/// (Mon → Sun). A cell glows green the further under the limit the person was,
/// shows a faint red on over-limit days, and stays muted where there's no data.
class ProgressGrid extends StatelessWidget {
  const ProgressGrid({super.key, required this.profile, this.columns = 18});

  final Profile profile;
  final int columns;

  @override
  Widget build(BuildContext context) {
    final today = dateOnly(DateTime.now());
    // Monday of the current week, then walk back (columns - 1) weeks.
    final currentMonday = today.subtract(Duration(days: today.weekday - 1));
    final firstMonday =
        currentMonday.subtract(Duration(days: 7 * (columns - 1)));
    final byDay = profile.byDay;

    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 4.0;
        final cell = (constraints.maxWidth - gap * (columns - 1)) / columns;

        return Column(
          children: [
            for (var row = 0; row < 7; row++) ...[
              Row(
                children: [
                  for (var col = 0; col < columns; col++) ...[
                    _cell(
                      context,
                      byDay,
                      firstMonday.add(Duration(days: col * 7 + row)),
                      today,
                      cell,
                    ),
                    if (col < columns - 1) const SizedBox(width: gap),
                  ],
                ],
              ),
              if (row < 6) const SizedBox(height: gap),
            ],
          ],
        );
      },
    );
  }

  Widget _cell(
    BuildContext context,
    Map<DateTime, DailyRecord> byDay,
    DateTime day,
    DateTime today,
    double size,
  ) {
    // The underlying signal is a single boolean per day — under the limit or
    // not — so each cell is just green (met), red (missed), or muted (no data).
    Color color;
    if (day.isAfter(today)) {
      color = Colors.transparent; // days that haven't happened yet
    } else {
      final r = byDay[day];
      if (r == null) {
        color = context.cSurfaceHi;
      } else if (r.limitMet) {
        color = AppColors.primary;
      } else {
        color = AppColors.danger;
      }
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(3),
      ),
    );
  }
}

/// Simple two-state legend for the progress grid: under vs over the limit.
class ProgressLegend extends StatelessWidget {
  const ProgressLegend({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        _LegendKey(color: AppColors.primary, label: 'Under limit'),
        const SizedBox(width: 14),
        _LegendKey(color: AppColors.danger, label: 'Over'),
      ],
    );
  }
}

class _LegendKey extends StatelessWidget {
  const _LegendKey({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 11,
          height: 11,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: appFont(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: context.cTextTer,
          ),
        ),
      ],
    );
  }
}
