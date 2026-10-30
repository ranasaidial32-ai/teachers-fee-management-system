// lib/features/student/presentation/pages/student_fee_page.dart
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/providers/providers.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../teacher/data/fee_repository.dart';
import '../../../teacher/presentation/widgets/fee_status_badge.dart';
import '../../data/student_repository.dart';

// ── Providers ─────────────────────────────────────────────────────────────────

final _selectedMonthProvider = StateProvider.autoDispose<String>((_) {
  final now = DateTime.now();
  return '${now.year}-${now.month.toString().padLeft(2, '0')}';
});

final _studentFeeProvider =
    FutureProvider.autoDispose.family<StudentFeeSummary, String>(
  (ref, month) async {
    final repo   = StudentRepository(apiClient: ref.watch(apiClientProvider));
    final result = await repo.getMyFees(month: month);
    if (result.isSuccess) return result.data!;
    throw Exception(result.error);
  },
);

// ── Page ──────────────────────────────────────────────────────────────────────

class StudentFeePage extends ConsumerWidget {
  const StudentFeePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedMonth = ref.watch(_selectedMonthProvider);
    final feesAsync     = ref.watch(_studentFeeProvider(selectedMonth));

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Fees'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: _MonthNav(
            month: selectedMonth,
            onPrev: () {
              ref.read(_selectedMonthProvider.notifier).state =
                  _offsetMonth(selectedMonth, -1);
            },
            onNext: () {
              final next    = _offsetMonth(selectedMonth, 1);
              final current = _currentMonth();
              if (next.compareTo(current) <= 0) {
                ref.read(_selectedMonthProvider.notifier).state = next;
              }
            },
          ),
        ),
      ),
      body: RefreshIndicator(
        color:     AppTheme.primaryTeal,
        onRefresh: () => ref.refresh(_studentFeeProvider(selectedMonth).future),
        child: feesAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 48, color: Colors.grey),
                const SizedBox(height: 12),
                Text(err.toString().replaceAll('Exception: ', '')),
                const SizedBox(height: 16),
                OutlinedButton(
                  onPressed: () =>
                      ref.invalidate(_studentFeeProvider(selectedMonth)),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
          data: (summary) => _FeeContent(summary: summary),
        ),
      ),
    );
  }

  static String _offsetMonth(String month, int offset) {
    final parts = month.split('-');
    final date  = DateTime(
      int.parse(parts[0]),
      int.parse(parts[1]) + offset,
    );
    return '${date.year}-${date.month.toString().padLeft(2, '0')}';
  }

  static String _currentMonth() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}';
  }
}

// ── Fee Content ───────────────────────────────────────────────────────────────

class _FeeContent extends StatelessWidget {
  const _FeeContent({required this.summary});
  final StudentFeeSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [

        // ── Total Due Banner ────────────────────────────────────────────────
        if (summary.totalDue > 0)
          Container(
            padding: const EdgeInsets.all(16),
            margin:  const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              // FIX: withOpacity → withValues(alpha:)
              color: summary.overdue > 0
                  ? AppTheme.errorRed.withValues(alpha: 0.08)
                  : AppTheme.primaryTeal.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: summary.overdue > 0
                    ? AppTheme.errorRed.withValues(alpha: 0.3)
                    : AppTheme.primaryTeal.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  summary.overdue > 0
                      ? Icons.warning_amber_rounded
                      : Icons.account_balance_wallet_outlined,
                  color: summary.overdue > 0
                      ? AppTheme.errorRed
                      : AppTheme.primaryTeal,
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '₹${NumberFormat('#,##,###').format(summary.totalDue)} due',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize:   18,
                        fontWeight: FontWeight.w700,
                        color: summary.overdue > 0
                            ? AppTheme.errorRed
                            : AppTheme.primaryTeal,
                      ),
                    ),
                    Text(
                      summary.overdue > 0
                          ? '${summary.overdue} payment'
                            '${summary.overdue > 1 ? 's' : ''} overdue'
                          : '${summary.pending} payment'
                            '${summary.pending > 1 ? 's' : ''} pending',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: summary.overdue > 0
                            ? AppTheme.errorRed
                            : AppTheme.primaryTeal,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ).animate().fadeIn(),

        // ── Fee Cards ──────────────────────────────────────────────────────
        if (summary.fees.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(40),
              child: Column(
                children: [
                  Icon(
                    Icons.receipt_long_outlined,
                    size:  56,
                    // FIX: withValues(alpha:)
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.2),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No fee records this month',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          ...summary.fees.asMap().entries.map((entry) {
            final fee = entry.value;
            // FIX: fee.batch is now defined — uses BatchInfo from FeeModel
            final batchName = fee.batch?.name ?? 'Batch';
            return _FeeCard(fee: fee, batchName: batchName)
                .animate(delay: (entry.key * 60).ms)
                .fadeIn()
                .slideY(begin: 0.1);
          }),
      ],
    );
  }
}

// ── Fee Card ──────────────────────────────────────────────────────────────────

class _FeeCard extends StatelessWidget {
  const _FeeCard({required this.fee, required this.batchName});
  final FeeModel fee;
  final String   batchName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      margin:  const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color:        theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          // FIX: withValues(alpha:)
          color: fee.isOverdue
              ? AppTheme.statusOverdue.withValues(alpha: 0.3)
              : theme.colorScheme.outlineVariant,
          width: fee.isOverdue ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          // Status icon
          Container(
            width:  44,
            height: 44,
            decoration: BoxDecoration(
              color:        AppTheme.feeStatusBackground(fee.status),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              fee.isPaid
                  ? Icons.check_circle_rounded
                  : fee.isOverdue
                      ? Icons.warning_rounded
                      : Icons.schedule_rounded,
              color: AppTheme.feeStatusColor(fee.status),
              size:  22,
            ),
          ),
          const SizedBox(width: 14),

          // Batch info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  batchName,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  fee.isPaid
                      ? 'Paid on ${_formatDate(fee.paidAt)}'
                      : '₹${NumberFormat('#,##,###').format(fee.amountDue)} due',
                  style: theme.textTheme.bodySmall?.copyWith(
                    // FIX: withValues(alpha:)
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ),

          FeeStatusBadge(status: fee.status),
        ],
      ),
    );
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null) return '—';
    try {
      return DateFormat('dd MMM').format(DateTime.parse(dateStr).toLocal());
    } catch (_) {
      return '—';
    }
  }
}

// ── Month Navigator ───────────────────────────────────────────────────────────

class _MonthNav extends StatelessWidget {
  const _MonthNav({
    required this.month,
    required this.onPrev,
    required this.onNext,
  });
  final String       month;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final parts = month.split('-');
    final date  = DateTime(int.parse(parts[0]), int.parse(parts[1]));
    final label = DateFormat('MMMM yyyy').format(date);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon:      const Icon(Icons.chevron_left_rounded),
            onPressed: onPrev,
          ),
          Text(
            label,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          IconButton(
            icon:      const Icon(Icons.chevron_right_rounded),
            onPressed: onNext,
          ),
        ],
      ),
    );
  }
}