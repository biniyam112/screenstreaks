import 'package:flutter/material.dart';

import '../models/group_streak.dart';
import '../models/models.dart';
import '../theme.dart';
import '../widgets/group_month_grid.dart';

const _monthNames = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

/// The group's own history — a day counts only when everyone held.
class GroupHistoryScreen extends StatelessWidget {
  const GroupHistoryScreen({
    super.key,
    required this.groupName,
    required this.members,
    required this.limit,
    this.recovered = const {},
  });

  final String groupName;
  final List<Profile> members;
  final int limit;
  final Set<DateTime> recovered;

  List<DateTime> get _months {
    final today = dateOnly(DateTime.now());
    final days = <DateTime>[
      for (final m in members)
        for (final r in m.records) dateOnly(r.day),
    ]..sort();
    final start = days.isEmpty ? today : days.first;

    final out = <DateTime>[];
    var cursor = DateTime(today.year, today.month, 1);
    final firstMonth = DateTime(start.year, start.month, 1);
    while (!cursor.isBefore(firstMonth)) {
      out.add(cursor);
      cursor = DateTime(cursor.year, cursor.month - 1, 1);
    }
    return out;
  }

  void _explain(BuildContext context, DateTime day) {
    final d = dateOnly(day);
    final over = membersOverOn(members, d, limit);
    final wasRecovered = recovered.contains(d);

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.cSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (c) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 22, 24, 30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              wasRecovered
                  ? 'Covered by a pass'
                  : (over.isEmpty ? 'Everyone held' : 'Someone went over'),
              style: appFont(
                fontSize: 19,
                fontWeight: FontWeight.w800,
                color: context.cText,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              wasRecovered
                  ? "The group's weekly pass covered this day, so the streak "
                      'survived it.'
                  : (over.isEmpty
                      ? 'Every member stayed under the shared limit.'
                      : '${over.map((m) => m.listName).join(', ')} '
                          'went over or had an unjudged day.'),
              style: appFont(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: context.cTextSec,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final months = _months;

    return Scaffold(
      appBar: AppBar(title: Text(groupName)),
      body: SafeArea(
        child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
          itemCount: months.length,
          itemBuilder: (context, i) {
            final m = months[i];
            final showYear = i == 0 || months[i - 1].year != m.year;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (showYear) ...[
                  if (i > 0) const SizedBox(height: 12),
                  Text(
                    '${m.year}',
                    style: appFont(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: context.cText,
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                Text(
                  _monthNames[m.month - 1],
                  style: appFont(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: context.cText,
                  ),
                ),
                const SizedBox(height: 10),
                GroupMonthGrid(
                  members: members,
                  limit: limit,
                  month: m,
                  recovered: recovered,
                  onTapDay: (d) => _explain(context, d),
                ),
                const SizedBox(height: 26),
              ],
            );
          },
        ),
      ),
    );
  }
}
