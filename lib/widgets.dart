import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';

import 'theme.dart';

/// Primary action button — solid fill, no cartoon 3D.
class ModernButton extends StatelessWidget {
  const ModernButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.color = AppColors.primary,
    this.textColor = Colors.white,
    this.icon,
    this.expand = true,
    this.outlined = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final Color color;
  final Color textColor;
  final IconData? icon;
  final bool expand;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    final active = onPressed != null;
    final bg = outlined ? Colors.transparent : color;
    final fg = outlined ? context.cText : textColor;

    return Opacity(
      opacity: active ? 1 : 0.5,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: outlined ? Border.all(color: context.cDivider) : null,
            ),
            child: Row(
              mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(icon, color: fg, size: 18),
                  const SizedBox(width: 8),
                ],
                Text(
                  label,
                  style: appFont(
                    color: fg,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Simple themed card.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    // Frosted rather than solid, so the background gradient reads through.
    // The hairline keeps the edge visible where the blur and the backdrop
    // are close in tone.
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          width: double.infinity,
          padding: padding,
          decoration: BoxDecoration(
            color: context.cSurface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: context.cCardBorder),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Goal picker: −/+ (30-min steps) + preset chips.
class GoalPicker extends StatelessWidget {
  const GoalPicker({
    super.key,
    required this.minutes,
    required this.onChanged,
  });

  final int minutes;
  final ValueChanged<int> onChanged;

  static const _min = 30;
  static const _max = 1440;
  static const _step = 30;
  static const _presets = [60, 90, 120, 180, 240];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _StepButton(
              icon: Icons.remove_rounded,
              enabled: minutes > _min,
              onTap: () => onChanged((minutes - _step).clamp(_min, _max)),
            ),
            SizedBox(
              width: 150,
              child: Text(
                formatDuration(minutes),
                textAlign: TextAlign.center,
                style: appFont(
                  fontSize: 40,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primary,
                  letterSpacing: -1,
                  height: 1,
                ),
              ),
            ),
            _StepButton(
              icon: Icons.add_rounded,
              enabled: minutes < _max,
              onTap: () => onChanged((minutes + _step).clamp(_min, _max)),
            ),
          ],
        ),
        const SizedBox(height: 22),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: [
            for (final p in _presets)
              _PresetChip(
                label: formatDuration(p),
                selected: minutes == p,
                onTap: () => onChanged(p),
              ),
          ],
        ),
      ],
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.icon,
    required this.onTap,
    required this.enabled,
  });
  final IconData icon;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: context.cSurfaceHi,
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          color: enabled ? context.cText : context.cTextTer,
          size: 22,
        ),
      ),
    );
  }
}

class _PresetChip extends StatelessWidget {
  const _PresetChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.14)
              : context.cSurfaceHi,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: selected ? AppColors.primary : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Text(
          label,
          style: appFont(
            fontWeight: FontWeight.w600,
            fontSize: 13,
            color: selected ? AppColors.primary : context.cTextSec,
          ),
        ),
      ),
    );
  }
}
