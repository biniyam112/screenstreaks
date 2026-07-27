import 'package:flutter/material.dart';

import '../models/models.dart';
import '../theme.dart';

/// 7-day bar chart.
///
/// Boolean mode (no usedMinutes): uniform bars, green = met, red = missed.
/// Minutes mode (usedMinutes present): bars scale to usage, with the limit
/// drawn as a dashed line at ~62% height so over-limit days poke above it.
class WeeklyBarChart extends StatelessWidget {
  const WeeklyBarChart({super.key, required this.profile});
  final Profile profile;

  static const _plotHeight = 96.0;
  static const _limitFrac = 0.62; // where the limit line sits in the plot
  static const _dayLabels = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];

  @override
  Widget build(BuildContext context) {
    final today = dateOnly(DateTime.now());
    final days = List.generate(7, (i) => today.subtract(Duration(days: 6 - i)));

    final met = days.where((d) {
      final r = profile.byDay[d];
      return r != null && r.limitMet;
    }).length;

    final hasMinutes = days.any((d) => profile.byDay[d]?.usedMinutes != null);
    final limitLineTop = _plotHeight * (1 - _limitFrac);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Header(met: met),
        const SizedBox(height: 18),
        SizedBox(
          height: _plotHeight,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              if (hasMinutes)
                Positioned(
                  top: limitLineTop,
                  left: 0,
                  right: 34,
                  child: const _DashedLine(),
                ),
              if (hasMinutes)
                Positioned(
                  top: limitLineTop - 8,
                  right: 0,
                  child: Text(
                    'limit',
                    style: appFont(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: context.cTextTer,
                    ),
                  ),
                ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (int i = 0; i < days.length; i++) ...[
                    Expanded(
                      child: _Bar(
                        record: profile.byDay[days[i]],
                        isToday: days[i] == today,
                        limitMinutes: profile.dailyLimitMinutes,
                        hasMinutes: hasMinutes,
                      ),
                    ),
                    if (i < days.length - 1) const SizedBox(width: 7),
                  ],
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            for (int i = 0; i < days.length; i++) ...[
              Expanded(
                child: Center(
                  child: _DayLabel(
                    label: _dayLabels[days[i].weekday % 7],
                    isToday: days[i] == today,
                  ),
                ),
              ),
              if (i < days.length - 1) const SizedBox(width: 7),
            ],
          ],
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.met});
  final int met;

  @override
  Widget build(BuildContext context) {
    final color = met >= 5
        ? AppColors.primary
        : met >= 3
            ? AppColors.warning
            : AppColors.danger;

    return Row(
      children: [
        Text(
          'This week',
          style: appFont(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: context.cText,
          ),
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            '$met/7 days met',
            style: appFont(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({
    required this.record,
    required this.isToday,
    required this.limitMinutes,
    required this.hasMinutes,
  });

  final DailyRecord? record;
  final bool isToday;
  final int limitMinutes;
  final bool hasMinutes;

  static const _plotHeight = WeeklyBarChart._plotHeight;
  static const _limitFrac = WeeklyBarChart._limitFrac;

  @override
  Widget build(BuildContext context) {
    // Empty day: a short muted stub.
    if (record == null) {
      return _bar(
        context,
        height: 10,
        color: context.cDivider,
        gradientColor: null,
      );
    }

    final met = record!.limitMet;
    final color = met ? AppColors.primary : AppColors.danger;

    double height;
    if (hasMinutes && record!.usedMinutes != null && limitMinutes > 0) {
      // limit maps to _limitFrac of the plot; usage scales from there.
      final ratio = record!.usedMinutes! / limitMinutes;
      height = (ratio * _limitFrac * _plotHeight).clamp(8.0, _plotHeight);
    } else {
      height = met ? _plotHeight * 0.82 : _plotHeight * 0.6;
    }

    return _bar(context, height: height, color: color, gradientColor: color);
  }

  Widget _bar(
    BuildContext context, {
    required double height,
    required Color color,
    required Color? gradientColor,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOutCubic,
      height: height,
      decoration: BoxDecoration(
        gradient: gradientColor == null
            ? null
            : LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  gradientColor,
                  gradientColor.withValues(alpha: 0.55),
                ],
              ),
        color: gradientColor == null ? color : null,
        borderRadius: BorderRadius.circular(7),
        boxShadow: isToday && gradientColor != null
            ? [
                BoxShadow(
                  color: gradientColor.withValues(alpha: 0.45),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ]
            : null,
      ),
    );
  }
}

class _DayLabel extends StatelessWidget {
  const _DayLabel({required this.label, required this.isToday});
  final String label;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    if (isToday) {
      return Container(
        width: 22,
        height: 22,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          color: AppColors.primary,
          shape: BoxShape.circle,
        ),
        child: Text(
          label,
          style: appFont(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
      );
    }
    return Text(
      label,
      style: appFont(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: context.cTextTer,
      ),
    );
  }
}

class _DashedLine extends StatelessWidget {
  const _DashedLine();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 1,
      child: CustomPaint(
        painter: _DashedLinePainter(color: context.cTextTer),
        size: const Size(double.infinity, 1),
      ),
    );
  }
}

class _DashedLinePainter extends CustomPainter {
  _DashedLinePainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.5)
      ..strokeWidth = 1.2;
    const dash = 5.0, gap = 4.0;
    double x = 0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, 0), Offset(x + dash, 0), paint);
      x += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _DashedLinePainter old) => old.color != color;
}
