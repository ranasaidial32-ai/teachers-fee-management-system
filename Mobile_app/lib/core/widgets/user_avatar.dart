/// core/widgets/user_avatar.dart
/// Reusable avatar widget — used on profile page AND chat bubbles.
///
/// Logic:
///   avatarId != null  → show assets/avatars/avatar_<id>.png
///   avatarId == null  → show letter initial circle (existing behaviour)

import 'package:flutter/material.dart';
import '../constants/avatar_constants.dart';
import '../theme/app_theme.dart';

class UserAvatar extends StatelessWidget {
  const UserAvatar({
    super.key,
    required this.name,
    this.avatarId,
    this.radius   = 24,
    this.fontSize,
  });

  final String name;
  final int?   avatarId;
  final double radius;
  final double? fontSize;

  @override
  Widget build(BuildContext context) {
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    final effectiveFontSize = fontSize ?? radius * 0.6;

    // Has a valid preset avatar ID — show the image
    if (avatarId != null && avatarId! >= 1 && avatarId! <= 5) {
      return CircleAvatar(
        radius:          radius,
        backgroundColor: Colors.transparent,
        child: ClipOval(
          child: Image.asset(
            AvatarConstants.assetPath(avatarId!),
            width:  radius * 2,
            height: radius * 2,
            fit:    BoxFit.cover,
            // Graceful fallback to initial if asset missing
            errorBuilder: (_, __, ___) => _InitialCircle(
              initial:  initial,
              radius:   radius,
              fontSize: effectiveFontSize,
            ),
          ),
        ),
      );
    }

    // No avatar selected — show letter initial
    return _InitialCircle(
      initial:  initial,
      radius:   radius,
      fontSize: effectiveFontSize,
    );
  }
}

class _InitialCircle extends StatelessWidget {
  const _InitialCircle({
    required this.initial,
    required this.radius,
    required this.fontSize,
  });
  final String initial;
  final double radius;
  final double fontSize;

  @override
  Widget build(BuildContext context) => CircleAvatar(
    radius:          radius,
    backgroundColor: AppTheme.primaryTeal.withValues(alpha: 0.15),
    child: Text(
      initial,
      style: TextStyle(
        fontSize:   fontSize,
        fontWeight: FontWeight.w700,
        color:      AppTheme.primaryTeal,
      ),
    ),
  );
}