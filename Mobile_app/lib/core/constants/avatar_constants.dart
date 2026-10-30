/// core/constants/avatar_constants.dart
/// Central definition of the 5 preset avatars.
///
/// DESIGN CHOICE:
///   We use bundled Flutter asset images (no network, no R2 storage).
///   Each avatar has a unique integer ID (1–5) that is stored in the DB.
///   The ID is the single source of truth — the image path is derived from it.
///
/// ADD YOUR IMAGES:
///   Place your 5 images in:  assets/avatars/avatar_1.png
///                                            avatar_2.png
///                                            avatar_3.png
///                                            avatar_4.png
///                                            avatar_5.png
///
///   Then register the folder in pubspec.yaml:
///     flutter:
///       assets:
///         - assets/avatars/

import 'package:flutter/material.dart';

class AvatarConstants {
  AvatarConstants._();

  /// Total number of preset avatars
  static const int count = 5;

  /// Maps avatar_id (1–5) → asset path
  static String assetPath(int avatarId) {
    assert(avatarId >= 1 && avatarId <= 5, 'avatar_id must be 1–5');
    return 'assets/avatars/avatar_$avatarId.png';
  }

  /// All 5 avatar definitions for the picker grid
  static const List<AvatarOption> all = [
    AvatarOption(id: 1, label: 'Avatar 1', color: Color(0xFF1ABC9C)),
    AvatarOption(id: 2, label: 'Avatar 2', color: Color(0xFF3498DB)),
    AvatarOption(id: 3, label: 'Avatar 3', color: Color(0xFF9B59B6)),
    AvatarOption(id: 4, label: 'Avatar 4', color: Color(0xFFE67E22)),
    AvatarOption(id: 5, label: 'Avatar 5', color: Color(0xFFE74C3C)),
  ];
}

class AvatarOption {
  const AvatarOption({
    required this.id,
    required this.label,
    required this.color,  // Fallback ring colour if image fails to load
  });
  final int    id;
  final String label;
  final Color  color;
}