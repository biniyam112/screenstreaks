import 'package:flutter/material.dart';

import '../models/group_streak.dart';
import '../models/models.dart';
import '../theme.dart';

const _weekdayLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

/// One calendar month for a whole group. A day is green only when everyone
/// was provably under the shared limit — the same rule the streak uses.
class GroupMonthGrid extends StatelessWidget {
  const GroupMonthGrid({
    super.key,
    required this.members,
    required this.limit,
    required this.month,
    this.recovered = const {},
    this.showLabels = true,
    this.onTapDay,
  });

  final List<Profile> members;
  final int limit;
  final DateTime month;

  /// Days the group spent its pass on — they count as held.
  final Set<DateTime> recovered;

  final bool showLabels;
  final void Function(DateTime day)? onTapDay;

  /// null = nothing to judge, true = everyone under, false = someone missed.
  bool? _statusOn(DateTime day) {
    final d = dateOnly(day);
    if (recovered.contains(d)) return true;

    var anyRecord = false;
    var allUnder = true;
    for (final m in members) {
      final r = m.byDay[d];
      if (r == null || r.partial) return null; // can't judge the day
      anyRecord = true;
      if (!(r.limitMet && r.limitMinutes <= limit)) allUnder = false;
    }
    return anyRecord ? allUnder : null;
  }

  @override
  Widget build(BuildContext context) {
    final first = DateTime(month.year, month.month, 1);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final leading = first.weekday - 1;
    final today = dateOnly(DateTime.now());

    final cells = <Widget>[];
    for (var i = 0; i < leading; i++) {
      cells.add(const SizedBox.shrink());
    }
    for (var d = 1; d <= daysInMonth; d++) {
      final day = DateTime(month.year, month.month, d);
      final future = day.isAfter(today);

      Color fill;
      Color text = context.cTextSec;
      if (future) {
        fill = Colors.transparent;
        text = context.cTextTer.withValues(alpha: 0.4);
      } else {
        switch (_statusOn(day)) {
          case true:
            fill = AppColors.primary.withValues(alpha: 0.85);
            text = Colors.white;
          case false:
            fill = AppColors.danger.withValues(alpha: 0.75);
            text = Colors.white;
          case null:
            fill = context.cDivider.withValues(alpha: 0.5);
            text = context.cTextTer;
        }
      }

      cells.add(GestureDetector(
        onTap: onTapDay == null || future ? null : () => onTapDay!(day),
        child: Container(
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(7),
            border: day == today
                ? Border.all(color: AppColors.accent, width: 1.6)
                : null,
          ),
          alignment: Alignment.center,
          child: Text(
            '$d',
            style: appFont(
              fontSize: 10.5,
              fontWeight: day == today ? FontWeight.w800 : FontWeight.w600,
              color: text,
            ),
          ),
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
