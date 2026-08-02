import 'package:flutter/material.dart';

import '../models/models.dart';
import '../theme.dart';
import '../widgets/month_grid.dart';

const _monthNames = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

/// Every month since the first record, newest first. Year headers fall out
/// of the ordering, so new years appear on their own as time passes.
class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key, required this.profile});

  final Profile profile;

  List<DateTime> get _months {
    final today = dateOnly(DateTime.now());
    final days = profile.records.map((r) => dateOnly(r.day)).toList()..sort();
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

  @override
  Widget build(BuildContext context) {
    final months = _months;

    return Scaffold(
      appBar: AppBar(title: const Text('History')),
      body: SafeArea(
        child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
          itemCount: months.length,
          itemBuilder: (context, i) {
            final m = months[i];
            final showYear = i == 0 || months[i - 1].year != m.year;
            final met = profile.records
                .where((r) =>
                    r.day.year == m.year && r.day.month == m.month && r.limitMet)
                .length;

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
                Row(
                  children: [
                    Text(
                      _monthNames[m.month - 1],
                      style: appFont(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: context.cText,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '$met under',
                      style: appFont(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: context.cTextSec,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                MonthGrid(profile: profile, month: m),
                const SizedBox(height: 26),
              ],
            );
          },
        ),
      ),
    );
  }
}
