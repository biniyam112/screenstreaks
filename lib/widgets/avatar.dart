import 'package:flutter/material.dart';

import '../models/models.dart';
import '../theme.dart';

/// Profile picture when there is one, coloured initials when there isn't.
class Avatar extends StatelessWidget {
  const Avatar({super.key, required this.profile, this.size = 40});

  final Profile profile;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = profile.avatarColor ?? AppColors.primary;
    final url = profile.avatarUrl;

    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        shape: BoxShape.circle,
      ),
      child: url == null || url.isEmpty
          ? Text(
              profile.initials,
              style: appFont(
                fontSize: size * 0.36,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            )
          : Image.network(
              url,
              width: size,
              height: size,
              fit: BoxFit.cover,
              // Fall back to initials if the image fails rather than
              // showing a broken box.
              errorBuilder: (_, _, _) => Text(
                profile.initials,
                style: appFont(
                  fontSize: size * 0.36,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
            ),
    );
  }
}
