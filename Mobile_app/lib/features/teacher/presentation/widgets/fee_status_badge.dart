/// features/teacher/presentation/widgets/fee_status_badge.dart
/// Reusable status badge for fee payment status display.
///
/// PRD Reference: Section 04 — Payment Status States
///   Pending — not yet paid, within grace (Amber)
///   Overdue — grace period expired, unpaid (Red)
///   Paid    — marked paid by teacher (Green)
///
/// Used in: FeeManagementPage, StudentFeePage, BatchDetailPage

import 'package:flutter/material.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_theme.dart';

class FeeStatusBadge extends StatelessWidget {
  const FeeStatusBadge({
    super.key,
    required this.status,
    this.compact = false,
  });

  final String status;   // 'pending' | 'overdue' | 'paid'
  final bool   compact;

  @override
  Widget build(BuildContext context) {
    final color      = AppTheme.feeStatusColor(status);
    final bgColor    = AppTheme.feeStatusBackground(status);
    final label      = _label(status);
    final icon       = _icon(status);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8  : 10,
        vertical:   compact ? 3  : 5,
      ),
      decoration: BoxDecoration(
        color:        bgColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: compact ? 10 : 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize:   compact ? 10 : 11,
              fontWeight: FontWeight.w600,
              color:      color,
            ),
          ),
        ],
      ),
    );
  }

  String _label(String status) {
    switch (status.toLowerCase()) {
      case AppConstants.statusPaid:    return 'Paid';
      case AppConstants.statusOverdue: return 'Overdue';
      default:                         return 'Pending';
    }
  }

  IconData _icon(String status) {
    switch (status.toLowerCase()) {
      case AppConstants.statusPaid:    return Icons.check_circle_rounded;
      case AppConstants.statusOverdue: return Icons.warning_rounded;
      default:                         return Icons.schedule_rounded;
    }
  }
}