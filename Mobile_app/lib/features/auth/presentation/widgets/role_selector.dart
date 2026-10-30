/// features/auth/presentation/widgets/role_selector.dart
/// Role selection widget for the registration screen.
///
/// PRD Reference: Section 02 — User Roles & Personas
///   Teacher (admin): Create batches, manage fees, administer chat
///   Student (user):  View fees, receive notifications, participate in chat
///
/// Displays two selectable cards:
///   [Teacher Card] [Student Card]
/// Active card shows teal border + filled background.
///
/// Used in RegisterPage only.

import 'package:flutter/material.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_theme.dart';

class RoleSelector extends StatelessWidget {
  const RoleSelector({
    super.key,
    required this.selectedRole,
    required this.onRoleSelected,
  });

  final String                  selectedRole;
  final void Function(String)   onRoleSelected;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _RoleCard(
            role:       AppConstants.roleTeacher,
            label:      'Teacher',
            subtitle:   'Manage batches & fees',
            icon:       Icons.admin_panel_settings_rounded,
            isSelected: selectedRole == AppConstants.roleTeacher,
            onTap:      () => onRoleSelected(AppConstants.roleTeacher),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _RoleCard(
            role:       AppConstants.roleStudent,
            label:      'Student',
            subtitle:   'View fees & chat',
            icon:       Icons.school_rounded,
            isSelected: selectedRole == AppConstants.roleStudent,
            onTap:      () => onRoleSelected(AppConstants.roleStudent),
          ),
        ),
      ],
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.role,
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  final String   role;
  final String   label;
  final String   subtitle;
  final IconData icon;
  final bool     isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding:  const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.primaryTeal.withOpacity(0.08)
              : theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color:  isSelected
                    ? AppTheme.primaryTeal
                    : theme.colorScheme.outline,
            width:  isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Icon
            Container(
              width:  40,
              height: 40,
              decoration: BoxDecoration(
                color: isSelected
                    ? AppTheme.primaryTeal.withOpacity(0.12)
                    : theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                size:  22,
                color: isSelected
                       ? AppTheme.primaryTeal
                       : theme.colorScheme.onSurface.withOpacity(0.5),
              ),
            ),

            const SizedBox(height: 10),

            // Label
            Text(
              label,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color:      isSelected
                            ? AppTheme.primaryTeal
                            : theme.colorScheme.onSurface,
              ),
            ),

            const SizedBox(height: 2),

            // Subtitle
            Text(
              subtitle,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.55),
              ),
            ),

            const SizedBox(height: 8),

            // Selection indicator
            Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width:  16,
                  height: 16,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isSelected
                           ? AppTheme.primaryTeal
                           : Colors.transparent,
                    border: Border.all(
                      color: isSelected
                             ? AppTheme.primaryTeal
                             : theme.colorScheme.outline,
                      width: 1.5,
                    ),
                  ),
                  child: isSelected
                      ? const Icon(
                          Icons.check,
                          size:  10,
                          color: Colors.white,
                        )
                      : null,
                ),
                const SizedBox(width: 6),
                Text(
                  isSelected ? 'Selected' : 'Select',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: isSelected
                           ? AppTheme.primaryTeal
                           : theme.colorScheme.onSurface.withOpacity(0.4),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}