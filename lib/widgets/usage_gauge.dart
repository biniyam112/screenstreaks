import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

/// Half-circle gauge for today's live screen time (Android only, where we know
/// the exact minutes). The arc fills toward the daily limit and shifts colour
/// as usage climbs: green → amber → orange → red (over limit).
class UsageGauge extends StatelessWidget {
  const UsageGauge({
    super.key,
    required this.usedMinutes,
    required this.limitMinutes,
    this.size = 240,
  });

  final int usedMinutes;
  final int limitMinutes;
  final double size;

  static const _stroke = 16.0;

  /// Colour for a given used/limit ratio.
  static Color colorFor(double ratio) {
    if (ratio >= 1.0) return AppColors.danger;
    if (ratio >= 0.85) return AppColors.accent; // orange
    if (ratio >= 0.5) return AppColors.warning; // amber
    return AppColors.primary; // green
  }

  @override
  Widget build(BuildContext context) {
    final ratio = limitMinutes <= 0 ? 0.0 : usedMinutes / limitMinutes;
    final over = ratio > 1.0;
    final color = colorFor(ratio);

    final radius = (size - _stroke) / 2;
    final arcHeight = radius + _stroke / 2;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: size,
          height: arcHeight,
          child: Stack(
            alignment: Alignment.bottomCenter,
            children: [
              TweenAnimationBuilder<double>(
                duration: const Duration(milliseconds: 900),
                curve: Curves.easeOutCubic,
                tween: Tween(begin: 0, end: ratio.clamp(0.0, 1.0)),
                builder: (context, fill, _) => CustomPaint(
                  size: Size(size, arcHeight),
                  painter: _GaugePainter(
                    fill: fill,
                    color: color,
                    track: context.cSurfaceHi,
                    stroke: _stroke,
                  ),
                ),
              ),
              // Value sits in the bowl of the arc.
              Padding(
                padding: EdgeInsets.only(bottom: size * 0.04),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      formatDuration(usedMinutes),
                      style: appFont(
                        fontSize: size * 0.19,
                        fontWeight: FontWeight.w800,
                        height: 1,
                        letterSpacing: -1.5,
                        color: context.cText,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'of ${formatDuration(limitMinutes)}',
                      style: appFont(
                        fontSize: size * 0.058,
                        fontWeight: FontWeight.w600,
                        color: context.cTextSec,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            over ? 'Over limit' : '${(ratio * 100).round()}% of limit used',
            style: appFont(
              fontSize: size * 0.055,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}

class _GaugePainter extends CustomPainter {
  _GaugePainter({
    required this.fill,
    required this.color,
    required this.track,
    required this.stroke,
  });

  final double fill; // 0..1
  final Color color;
  final Color track;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = (size.width - stroke) / 2;
    final center = Offset(size.width / 2, radius + stroke / 2);
    final rect = Rect.fromCircle(center: center, radius: radius);

    // Top semicircle: start at 180° (left), sweep 180° over the top to 0°.
    const start = math.pi;
    const sweep = math.pi;

    final track$ = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = track;
    canvas.drawArc(rect, start, sweep, false, track$);

    if (fill > 0) {
      final fillPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = color;
      canvas.drawArc(rect, start, sweep * fill, false, fillPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _GaugePainter old) =>
      old.fill != fill || old.color != color || old.track != track;
}
