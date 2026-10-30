/// features/teacher/presentation/pages/fee_management_page.dart
/// Fee management screen for teachers.
///
/// PRD Reference: Section 04 — Fee Lifecycle
///   "Teacher marks payment as Paid manually"
///   PRD success metric: "Fee marking in <10s"
///
/// FEATURES:
///   - Month selector (billing cycle navigation)
///   - Summary bar: Total / Paid / Pending / Overdue counts
///   - Student fee list with status badges
///   - One-tap "Mark Paid" on each overdue/pending fee
///   - Pull to refresh

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';

import '../../../../core/providers/providers.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/fee_repository.dart';
import '../widgets/fee_status_badge.dart';

// ── State ─────────────────────────────────────────────────────────────────────

class _FeePageState {
  const _FeePageState({
    required this.batchId,
    required this.selectedMonth,
    this.markingFeeId,
  });
  final String  batchId;
  final String  selectedMonth;
  final String? markingFeeId;

  _FeePageState copyWith({String? selectedMonth, String? markingFeeId}) =>
      _FeePageState(
        batchId:       batchId,
        selectedMonth: selectedMonth ?? this.selectedMonth,
        markingFeeId:  markingFeeId,
      );
}

String _currentMonth() {
  final now = DateTime.now();
  return '${now.year}-${now.month.toString().padLeft(2, '0')}';
}

final _feePageStateProvider =
    StateProvider.autoDispose.family<_FeePageState, String>(
  (ref, batchId) => _FeePageState(
    batchId:       batchId,
    selectedMonth: _currentMonth(),
  ),
);

final _feeRepositoryProvider = Provider<FeeRepository>((ref) {
  return FeeRepository(apiClient: ref.watch(apiClientProvider));
});

final _batchFeesProvider = FutureProvider.autoDispose
    .family<BatchFeeResponse, ({String batchId, String month})>(
  (ref, args) async {
    final repo   = ref.watch(_feeRepositoryProvider);
    final result = await repo.getBatchFees(
      batchId: args.batchId,
      month:   args.month,
    );
    if (result.isSuccess) return result.data!;
    throw Exception(result.error);
  },
);

// ── Page ──────────────────────────────────────────────────────────────────────

class FeeManagementPage extends ConsumerWidget {
  const FeeManagementPage({super.key, required this.batchId});
  final String batchId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pageState  = ref.watch(_feePageStateProvider(batchId));
    final feesAsync  = ref.watch(
      _batchFeesProvider((
        batchId: batchId,
        month:   pageState.selectedMonth,
      )),
    );
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Fee Management'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: _MonthSelector(
            selectedMonth: pageState.selectedMonth,
            onMonthChanged: (month) {
              ref.read(_feePageStateProvider(batchId).notifier).update(
                (s) => s.copyWith(selectedMonth: month),
              );
            },
          ),
        ),
      ),
      body: RefreshIndicator(
        color:     AppTheme.primaryTeal,
        onRefresh: () => ref.refresh(
          _batchFeesProvider((
            batchId: batchId,
            month:   pageState.selectedMonth,
          )).future,
        ),
        child: feesAsync.when(
          loading: () =>
              const Center(child: CircularProgressIndicator()),
          error: (err, _) => Center(
            child: Text(err.toString().replaceAll('Exception: ', '')),
          ),
          data: (feeResponse) => Column(
            children: [
              // ── Summary Bar ───────────────────────────────────────────────
              _SummaryBar(summary: feeResponse.summary),

              // ── Fee List ──────────────────────────────────────────────────
              Expanded(
                child: feeResponse.fees.isEmpty
                    ? const Center(child: Text('No fee records this month.'))
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: feeResponse.fees.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final fee = feeResponse.fees[index];
                          final isMarking =
                              pageState.markingFeeId == fee.id;

                          return _FeeListItem(
                            fee:       fee,
                            isMarking: isMarking,
                            onMarkPaid: fee.isPaid
                                ? null
                                : () => _markPaid(
                                      context, ref, fee.id,
                                    ),
                          ).animate(delay: (index * 40).ms).fadeIn();
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Mark Paid ──────────────────────────────────────────────────────────────
  Future<void> _markPaid(
    BuildContext context,
    WidgetRef    ref,
    String       feeId,
  ) async {
    ref.read(_feePageStateProvider(batchId).notifier).update(
      (s) => s.copyWith(markingFeeId: feeId),
    );

    final repo   = ref.read(_feeRepositoryProvider);
    final result = await repo.markPaid(feeId);

    final pageState = ref.read(_feePageStateProvider(batchId));

    ref.read(_feePageStateProvider(batchId).notifier).update(
      (s) => s.copyWith(markingFeeId: null),
    );

    if (result.isSuccess) {
      // Refresh fee list
      ref.invalidate(
        _batchFeesProvider((
          batchId: batchId,
          month:   pageState.selectedMonth,
        )),
      );

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:         Text('Fee marked as paid ✓'),
            backgroundColor: AppTheme.successGreen,
            duration:        Duration(seconds: 2),
          ),
        );
      }
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:         Text(result.error ?? 'Failed to mark paid'),
            backgroundColor: AppTheme.errorRed,
          ),
        );
      }
    }
  }
}

// ── Month Selector ────────────────────────────────────────────────────────────

class _MonthSelector extends StatelessWidget {
  const _MonthSelector({
    required this.selectedMonth,
    required this.onMonthChanged,
  });
  final String                  selectedMonth;
  final void Function(String)   onMonthChanged;

  @override
  Widget build(BuildContext context) {
    final parts = selectedMonth.split('-');
    final date  = DateTime(int.parse(parts[0]), int.parse(parts[1]));
    final label = DateFormat('MMMM yyyy').format(date);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon:      const Icon(Icons.chevron_left_rounded),
            onPressed: () => onMonthChanged(_offsetMonth(selectedMonth, -1)),
          ),
          Text(
            label,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right_rounded),
            onPressed: () {
              final next    = _offsetMonth(selectedMonth, 1);
              final nowMonth = _currentMonth();
              if (next.compareTo(nowMonth) <= 0) {
                onMonthChanged(next);
              }
            },
          ),
        ],
      ),
    );
  }

  String _offsetMonth(String month, int offset) {
    final parts  = month.split('-');
    final date   = DateTime(int.parse(parts[0]), int.parse(parts[1]) + offset);
    return '${date.year}-${date.month.toString().padLeft(2, '0')}';
  }
}

// ── Summary Bar ───────────────────────────────────────────────────────────────

class _SummaryBar extends StatelessWidget {
  const _SummaryBar({required this.summary});
  final FeeSummary summary;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin:  const EdgeInsets.all(16),
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: BoxDecoration(
        color:        Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
      child: Row(
        children: [
          _SummaryItem(
            value: '${summary.total}',
            label: 'Total',
            color: AppTheme.primaryTeal,
          ),
          _SummaryItem(
            value: '${summary.paid}',
            label: 'Paid',
            color: AppTheme.statusPaid,
          ),
          _SummaryItem(
            value: '${summary.pending}',
            label: 'Pending',
            color: AppTheme.statusPending,
          ),
          _SummaryItem(
            value: '${summary.overdue}',
            label: 'Overdue',
            color: AppTheme.statusOverdue,
          ),
        ],
      ),
    );
  }
}

class _SummaryItem extends StatelessWidget {
  const _SummaryItem({
    required this.value,
    required this.label,
    required this.color,
  });
  final String value;
  final String label;
  final Color  color;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize:   22,
            fontWeight: FontWeight.w700,
            color:      color,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
          ),
        ),
      ],
    ),
  );
}

// ── Fee List Item ─────────────────────────────────────────────────────────────

class _FeeListItem extends StatelessWidget {
  const _FeeListItem({
    required this.fee,
    required this.isMarking,
    this.onMarkPaid,
  });
  final FeeModel    fee;
  final bool        isMarking;
  final VoidCallback? onMarkPaid;

  @override
  Widget build(BuildContext context) {
    final theme    = Theme.of(context);
    final student  = fee.student;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color:        theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: fee.isOverdue
              ? AppTheme.statusOverdue.withOpacity(0.3)
              : theme.colorScheme.outlineVariant,
        ),
      ),
      child: Row(
        children: [
          // Avatar
          CircleAvatar(
            radius:          20,
            backgroundColor: AppTheme.primaryTeal.withOpacity(0.1),
            child: Text(
              student?.name.isNotEmpty == true
                  ? student!.name[0].toUpperCase()
                  : '?',
              style: const TextStyle(
                color:      AppTheme.primaryTeal,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Name + Amount
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  student?.name ?? 'Unknown',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '₹${NumberFormat('#,##,###').format(fee.amountDue)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withOpacity(0.5),
                  ),
                ),
              ],
            ),
          ),

          // Status Badge
          FeeStatusBadge(status: fee.status),
          const SizedBox(width: 8),

          // Mark Paid Button
          if (!fee.isPaid)
            isMarking
                ? const SizedBox(
                    width:  24,
                    height: 24,
                    child:  CircularProgressIndicator(strokeWidth: 2),
                  )
                : IconButton(
                    icon:      const Icon(Icons.check_circle_outline),
                    color:     AppTheme.successGreen,
                    tooltip:   'Mark as Paid',
                    onPressed: onMarkPaid,
                  )
          else
            const Icon(
              Icons.check_circle_rounded,
              color: AppTheme.statusPaid,
              size:  24,
            ),
        ],
      ),
    );
  }
}