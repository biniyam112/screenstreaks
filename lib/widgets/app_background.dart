import 'package:flutter/material.dart';

import '../colors.dart';

/// The gradient behind every screen — blue at the top through plum to a warm
/// base, with a soft bloom in the middle and a vignette at the edges. Fixed
/// rather than scrolling, so content moves over it.
class AppBackground extends StatelessWidget {
  const AppBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;

    return Stack(
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: context.cGradient,
                stops: const [0.0, 0.5, 1.0],
              ),
            ),
          ),
        ),
        // Bloom — lifts the middle so cards there have something to sit on.
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0, -0.2),
                radius: 0.9,
                colors: [context.cBloom, Colors.transparent],
              ),
            ),
          ),
        ),
        // Vignette — keeps the edges from competing with content.
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.center,
                radius: 1.1,
                colors: [
                  Colors.transparent,
                  (dark ? Colors.black : const Color(0xFF1E1932))
                      .withValues(alpha: dark ? 0.35 : 0.18),
                ],
                stops: const [0.55, 1.0],
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }
}
