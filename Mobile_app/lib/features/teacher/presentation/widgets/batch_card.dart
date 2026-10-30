/// features/teacher/presentation/widgets/batch_card.dart
/// Batch summary card for the teacher home page list.
///
/// Displays: Name, student count, monthly fee, grace period
/// Quick actions: Open Chat, Manage Fees, View Detail

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_theme.dart';
import '../../data/batch_repository.dart';

class BatchCard extends StatelessWidget {
  const BatchCard({
    super.key,
    required this.batch,
    required this.onTap,
    required this.onManageFees,
    required this.onOpenChat,
  });

  final BatchModel   batch;
  final VoidCallback onTap;
  final VoidCallback onManageFees;
  final VoidCallback onOpenChat;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: InkWell(
        onTap:         onTap,
        borderRadius:  BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header Row ──────────────────────────────────────────────────
              Row(
                children: [
                  // Batch icon
                  Container(
                    width:  44,
                    height: 44,
                    decoration: BoxDecoration(
                      color:        AppTheme.primaryTeal.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.class_rounded,
                      color: AppTheme.primaryTeal,
                      size:  22,
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Name + students
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          batch.name,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${batch.studentCount} student${batch.studentCount != 1 ? 's' : ''}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withOpacity(0.5),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Active indicator
                  if (batch.isActive)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color:        AppTheme.successGreen.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        'Active',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize:   10,
                          fontWeight: FontWeight.w600,
                          color:      AppTheme.successGreen,
                        ),
                      ),
                    ),
                ],
              ),

              const SizedBox(height: 12),
              Divider(color: theme.colorScheme.outlineVariant, height: 1),
              const SizedBox(height: 12),

              // ── Metrics Row ─────────────────────────────────────────────────
              Row(
                children: [
                  _MetricChip(
                    icon:  Icons.currency_rupee_rounded,
                    label: '₹${NumberFormat('#,##,###').format(batch.feeAmount)}/mo',
                  ),
                  const SizedBox(width: 8),
                  _MetricChip(
                    icon:  Icons.hourglass_bottom_rounded,
                    label: '${batch.gracePeriodDays}d grace',
                  ),
                  const SizedBox(width: 8),
                  _MetricChip(
                    icon:  Icons.schedule_outlined,
                    label: '${batch.durationYears}yr',
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // ── Action Buttons ──────────────────────────────────────────────
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onOpenChat,
                      icon:      const Icon(Icons.chat_outlined, size: 16),
                      label:     const Text('Chat'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 38),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: onManageFees,
                      icon:      const Icon(
                        Icons.account_balance_wallet_outlined,
                        size: 16,
                      ),
                      label:     const Text('Fees'),
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(0, 38),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({required this.icon, required this.label});
  final IconData icon;
  final String   label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color:        Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(6),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: AppTheme.primaryTeal),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(
            fontFamily: 'Inter',
            fontSize:   11,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    ),
  );
}