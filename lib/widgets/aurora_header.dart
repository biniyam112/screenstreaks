import 'package:flutter/material.dart';

import '../theme.dart';

/// Soft coloured wash at the top of a screen that fades into the page.
/// Each tab gets its own hue so screens feel distinct without shouting.
class AuroraHeader extends StatelessWidget {
  const AuroraHeader({
    super.key,
    required this.title,
    required this.tint,
    this.trailing,
    this.height = 132,
  });

  final String title;
  final Color tint;
  final Widget? trailing;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      // Transparent — the app's gradient runs behind it, so painting a solid
      // colour here left a strip that didn't match the rest of the screen.
      color: Colors.transparent,
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: appFont(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: context.cText,
                ),
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}

/// Rounded, borderless card — separation comes from fill, not a line.
class SoftCard extends StatelessWidget {
  const SoftCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.color,
  });

  final Widget child;
  final EdgeInsets padding;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? context.cSurface,
        borderRadius: BorderRadius.circular(22),
      ),
      child: child,
    );
  }
}
