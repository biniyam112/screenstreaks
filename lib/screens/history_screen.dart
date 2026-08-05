import 'package:flutter/material.dart';

import '../models/models.dart';
import '../theme.dart';
import '../widgets/month_grid.dart';
import '../widgets.dart';
import '../data/repo_scope.dart';

const _monthNames = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

/// Every month since the first record, newest first. Year headers fall out
/// of the ordering, so new years appear on their own as time passes.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key, required this.profile});

  final Profile profile;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  late Profile profile = widget.profile;

  Future<void> _onTapDay(DateTime day, DailyRecord? record) async {
    if (record == null || record.limitMet) return;

    final ok = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: context.cSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 22, 24, 30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Recover this day?',
              style: appFont(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: context.cText,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Spend a pass and this day counts as met. One a week — '
              'use it when the app got it wrong, or life did.',
              textAlign: TextAlign.center,
              style: appFont(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: context.cTextSec,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 22),
            ModernButton(
              label: 'Spend a pass',
              onPressed: () => Navigator.pop(sheetContext, true),
            ),
          ],
        ),
      ),
    );

    if (ok != true || !mounted) return;
    final repo = RepoScope.of(context);
    try {
      await repo.spendPass(day);
      final fresh = await repo.me();
      if (mounted) setState(() => profile = fresh);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

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
                MonthGrid(profile: profile, month: m, onTapDay: _onTapDay),
                const SizedBox(height: 26),
              ],
            );
          },
        ),
      ),
    );
  }
}
