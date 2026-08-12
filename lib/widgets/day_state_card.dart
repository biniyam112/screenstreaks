import 'package:flutter/material.dart';

import '../theme.dart';

/// Where today stands against the limit. iOS never gives an app the minutes,
/// only two signals — 30 minutes out, and over — so this shows three states
/// rather than pretending to a percentage.
class DayStateCard extends StatelessWidget {
  const DayStateCard({
    super.key,
    required this.state,
    required this.limitMinutes,
    this.warnedAt,
    this.overAt,
  });

  /// 0 under, 1 approaching, 2 over.
  final int state;
  final int limitMinutes;
  final DateTime? warnedAt;
  final DateTime? overAt;

  Color get _color => switch (state) {
        2 => AppColors.danger,
        1 => AppColors.accent,
        _ => AppColors.primary,
      };

  String get _title => switch (state) {
        2 => 'Over your limit',
        1 => 'Half an hour left',
        _ => 'Under your limit',
      };

  String _clock(DateTime t) {
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m${t.hour < 12 ? 'am' : 'pm'}';
  }

  String get _detail {
    final h = limitMinutes ~/ 60;
    final m = limitMinutes % 60;
    final limit = m == 0 ? '${h}h' : '${h}h$m';
    if (state == 2 && overAt != null) {
      return 'Passed $limit at ${_clock(overAt!)}';
    }
    if (state == 1 && warnedAt != null) {
      return 'Warned at ${_clock(warnedAt!)} · $limit limit';
    }
    return "We'll know 30 minutes before you hit $limit";
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.cSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.cDivider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _title,
            style: appFont(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: _color,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (var i = 0; i < 3; i++) ...[
                Expanded(
                  flex: i == 0 ? 2 : 1,
                  child: Container(
                    height: 8,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      color: i <= state
                          ? switch (i) {
                              2 => AppColors.danger,
                              1 => AppColors.accent,
                              _ => AppColors.primary,
                            }
                          : context.cDivider,
                    ),
                  ),
                ),
                if (i < 2) const SizedBox(width: 4),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _detail,
            style: appFont(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: context.cTextSec,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}
