import 'package:flutter/material.dart';

import '../models/models.dart';
import '../theme.dart';

const _weekdayLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

/// One calendar month as weeks-of-rows, aligned to weekday columns.
class MonthGrid extends StatelessWidget {
  const MonthGrid({
    super.key,
    required this.profile,
    required this.month,
    this.showLabels = true,
    this.onTapDay,
    this.pending = const {},
  });

  final Profile profile;

  /// Any date within the month to render.
  final DateTime month;

  final bool showLabels;

  /// Tapping a logged day — used to spend a pass on a miss.
  final void Function(DateTime day, DailyRecord? record)? onTapDay;

  /// Days recorded on this phone but not yet pushed to the server. Distinct
  /// from unjudged — we know the answer, it just hasn't synced.
  final Set<DateTime> pending;

  @override
  Widget build(BuildContext context) {
    final first = DateTime(month.year, month.month, 1);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final leading = first.weekday - 1; // Monday = 0
    final today = dateOnly(DateTime.now());
    final byDay = profile.byDay;

    final cells = <Widget>[];
    for (var i = 0; i < leading; i++) {
      cells.add(const SizedBox.shrink());
    }
    for (var d = 1; d <= daysInMonth; d++) {
      final day = DateTime(month.year, month.month, d);
      final record = byDay[day];
      cells.add(GestureDetector(
        onTap: onTapDay == null || day.isAfter(today)
            ? null
            : () => onTapDay!(day, record),
        child: _Cell(
          day: day,
          record: record,
          isToday: day == today,
          isFuture: day.isAfter(today),
          isPending: pending.contains(day),
        ),
      ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showLabels) ...[
          Row(
            children: [
              for (final l in _weekdayLabels)
                Expanded(
                  child: Center(
                    child: Text(
                      l,
                      style: appFont(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: context.cTextTer,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
        ],
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 4,
          crossAxisSpacing: 4,
          children: cells,
        ),
      ],
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({
    required this.day,
    required this.record,
    required this.isToday,
    required this.isFuture,
    this.isPending = false,
  });

  final DateTime day;
  final DailyRecord? record;
  final bool isToday;
  final bool isFuture;
  final bool isPending;

  @override
  Widget build(BuildContext context) {
    Color fill;
    Color text = context.cTextSec;

    if (isFuture) {
      fill = Colors.transparent;
      text = context.cTextTer.withValues(alpha: 0.4);
    } else if (isPending) {
      // Recorded here but not yet on the server — we know, nobody else does.
      fill = AppColors.accent.withValues(alpha: 0.45);
      text = Colors.white;
    } else if (record == null) {
      fill = context.cDivider.withValues(alpha: 0.35);
      text = context.cTextTer;
    } else if (record!.partial) {
      // Monitoring started mid-day — shown, but not judged.
      fill = context.cDivider.withValues(alpha: 0.6);
      text = context.cTextSec;
    } else if (record!.limitMet) {
      fill = AppColors.primary.withValues(alpha: 0.85);
      text = Colors.white;
    } else {
      fill = AppColors.danger.withValues(alpha: 0.75);
      text = Colors.white;
    }

    return Container(
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(7),
        border: isToday
            ? Border.all(color: AppColors.accent, width: 1.6)
            : null,
      ),
      alignment: Alignment.center,
      child: Text(
        '${day.day}',
        style: appFont(
          fontSize: 10.5,
          fontWeight: isToday ? FontWeight.w800 : FontWeight.w600,
          color: text,
        ),
      ),
    );
  }
}
