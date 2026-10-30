/// features/student/presentation/pages/student_home_page.dart
/// Student dashboard — enrolled batches + current month fee summary.
///
/// PRD Reference: Section 02 — Student Role
///   "View payment status & history"
///   "Participate in batch chat"
///   "Auto-download teacher files"
///
/// SECTIONS:
///   1. Fee Summary Card — total due this month with status breakdown
///   2. My Batches — list of enrolled batches with chat + fee quick access
///   3. Overdue Alert Banner — shown when any fee is overdue

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import 'package:shimmer/shimmer.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/providers/providers.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../teacher/data/batch_repository.dart';
import '../../../teacher/presentation/widgets/fee_status_badge.dart';
import '../../data/student_repository.dart';

// ── Providers ─────────────────────────────────────────────────────────────────

final _studentRepositoryProvider = Provider<StudentRepository>((ref) {
  return StudentRepository(apiClient: ref.watch(apiClientProvider));
});

final _myFeesProvider =
    FutureProvider.autoDispose<StudentFeeSummary>((ref) async {
  final repo   = ref.watch(_studentRepositoryProvider);
  final result = await repo.getMyFees();
  if (result.isSuccess) return result.data!;
  throw Exception(result.error);
});

final _myBatchesProvider =
    FutureProvider.autoDispose<List<BatchModel>>((ref) async {
  final repo   = ref.watch(_studentRepositoryProvider);
  final result = await repo.getMyBatches();
  if (result.isSuccess) return result.data!;
  throw Exception(result.error);
});

// ── Page ──────────────────────────────────────────────────────────────────────

class StudentHomePage extends ConsumerWidget {
  const StudentHomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState   = ref.watch(authStateProvider);
    final feesAsync   = ref.watch(_myFeesProvider);
    final batchesAsync = ref.watch(_myBatchesProvider);
    final theme       = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Hi, ${authState.userName?.split(' ').first ?? 'Student'} 👋',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              'Your fee dashboard',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.5),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon:      const Icon(Icons.notifications_outlined),
            onPressed: () => context.go('/student/notifications'),
          ),
        ],
      ),
      body: RefreshIndicator(
        color:     AppTheme.primaryTeal,
        onRefresh: () async {
          ref.invalidate(_myFeesProvider);
          ref.invalidate(_myBatchesProvider);
        },
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [

            // ── Fee Summary Card ─────────────────────────────────────────────
            SliverToBoxAdapter(
              child: feesAsync.when(
                loading: () => _FeeCardShimmer(),
                error:   (_, __) => const SizedBox.shrink(),
                data:    (fees) => _FeeSummaryCard(summary: fees),
              ),
            ),

            // ── Overdue Alert ────────────────────────────────────────────────
            SliverToBoxAdapter(
              child: feesAsync.maybeWhen(
                data: (fees) => fees.overdue > 0
                    ? _OverdueBanner(
                        overdueCount: fees.overdue,
                        totalDue:     fees.totalDue,
                        onViewFees:   () => context.go('/student/fees'),
                      )
                    : const SizedBox.shrink(),
                orElse: () => const SizedBox.shrink(),
              ),
            ),

            // ── Section Title: My Batches ─────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: Text(
                  'My Batches',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),

            // ── Batch List ────────────────────────────────────────────────────
            batchesAsync.when(
              loading: () => const SliverToBoxAdapter(
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (err, _) => SliverToBoxAdapter(
                child: _BatchErrorState(
                  onRetry: () => ref.invalidate(_myBatchesProvider),
                ),
              ),
              data: (batches) {
                if (batches.isEmpty) {
                  return const SliverToBoxAdapter(
                    child: _NoBatchesState(),
                  );
                }
                return SliverPadding(
                  padding: const EdgeInsets.only(
                    left: 16, right: 16, bottom: 80,
                  ),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final batch = batches[index];
                        return _StudentBatchCard(
                          batch:      batch,
                          onOpenChat: () => context.go(
                            '/chat/${batch.id}',
                            extra: {'name': batch.name},
                          ),
                          onViewFees: () => context.go('/student/fees'),
                        ).animate(delay: (index * 60).ms).fadeIn().slideY(
                          begin: 0.15,
                          end:   0,
                        );
                      },
                      childCount: batches.length,
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ── Fee Summary Card ──────────────────────────────────────────────────────────

class _FeeSummaryCard extends StatelessWidget {
  const _FeeSummaryCard({required this.summary});
  final StudentFeeSummary summary;

  @override
  Widget build(BuildContext context) {
    final month = summary.currentMonth;
    final parts = month.split('-');
    final date  = DateTime(int.parse(parts[0]), int.parse(parts[1]));
    final label = DateFormat('MMMM yyyy').format(date);

    return Container(
      margin:  const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: summary.overdue > 0
              ? [AppTheme.errorRed, const Color(0xFFEF4444)]
              : [AppTheme.primaryTeal, AppTheme.primaryTealLight],
          begin: Alignment.topLeft,
          end:   Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: (summary.overdue > 0
                    ? AppTheme.errorRed
                    : AppTheme.primaryTeal)
                .withOpacity(0.25),
            blurRadius: 12,
            offset:     const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  color:      Colors.white70,
                  fontSize:   13,
                ),
              ),
              if (summary.overdue > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color:        Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'Action Required',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize:   11,
                      fontWeight: FontWeight.w600,
                      color:      Colors.white,
                    ),
                  ),
                ),
            ],
          ),

          const SizedBox(height: 12),

          // Total Due
          Text(
            summary.totalDue > 0
                ? '₹${NumberFormat('#,##,###').format(summary.totalDue)}'
                : 'All Clear ✓',
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize:   32,
              fontWeight: FontWeight.w700,
              color:      Colors.white,
            ),
          ),

          const SizedBox(height: 4),

          Text(
            summary.totalDue > 0 ? 'Total due this month' : 'All fees paid',
            style: const TextStyle(
              fontFamily: 'Inter',
              color:      Colors.white70,
              fontSize:   13,
            ),
          ),

          const SizedBox(height: 16),

          // Status breakdown
          Row(
            children: [
              _StatusPill(
                label: '${summary.paid} Paid',
                color: Colors.white.withOpacity(0.85),
              ),
              const SizedBox(width: 8),
              _StatusPill(
                label: '${summary.pending} Pending',
                color: Colors.white.withOpacity(0.85),
              ),
              if (summary.overdue > 0) ...[
                const SizedBox(width: 8),
                _StatusPill(
                  label: '${summary.overdue} Overdue',
                  color: Colors.white,
                  bold:  true,
                ),
              ],
            ],
          ),
        ],
      ),
    ).animate().fadeIn(duration: 500.ms).slideY(begin: -0.05);
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.label,
    required this.color,
    this.bold = false,
  });
  final String label;
  final Color  color;
  final bool   bold;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color:        Colors.white.withOpacity(0.15),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      label,
      style: TextStyle(
        fontFamily: 'Inter',
        fontSize:   11,
        fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
        color:      color,
      ),
    ),
  );
}

// ── Overdue Banner ────────────────────────────────────────────────────────────

class _OverdueBanner extends StatelessWidget {
  const _OverdueBanner({
    required this.overdueCount,
    required this.totalDue,
    required this.onViewFees,
  });
  final int          overdueCount;
  final int          totalDue;
  final VoidCallback onViewFees;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin:  const EdgeInsets.fromLTRB(16, 0, 16, 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color:        AppTheme.errorRed.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppTheme.errorRed.withOpacity(0.3),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            color: AppTheme.errorRed,
            size:  22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$overdueCount fee${overdueCount > 1 ? 's' : ''} overdue. '
              'Please pay ₹${NumberFormat('#,##,###').format(totalDue)} to avoid issues.',
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize:   13,
                color:      AppTheme.errorRed,
              ),
            ),
          ),
          TextButton(
            onPressed: onViewFees,
            style: TextButton.styleFrom(
              foregroundColor: AppTheme.errorRed,
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            child: const Text('View'),
          ),
        ],
      ),
    ).animate().fadeIn().shake(hz: 1);
  }
}

// ── Student Batch Card ────────────────────────────────────────────────────────

class _StudentBatchCard extends StatelessWidget {
  const _StudentBatchCard({
    required this.batch,
    required this.onOpenChat,
    required this.onViewFees,
  });
  final BatchModel   batch;
  final VoidCallback onOpenChat;
  final VoidCallback onViewFees;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Batch name + fee
            Row(
              children: [
                Container(
                  width:  40,
                  height: 40,
                  decoration: BoxDecoration(
                    color:        AppTheme.primaryTeal.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.class_rounded,
                    color: AppTheme.primaryTeal,
                    size:  20,
                  ),
                ),
                const SizedBox(width: 12),
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
                      Text(
                        '₹${NumberFormat('#,##,###').format(batch.feeAmount)}/month',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withOpacity(0.5),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Actions
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onOpenChat,
                    icon:      const Icon(Icons.chat_outlined, size: 16),
                    label:     const Text('Chat'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 38),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onViewFees,
                    icon:      const Icon(
                      Icons.receipt_long_outlined,
                      size: 16,
                    ),
                    label: const Text('My Fees'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 38),
                    ),
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

// ── Utility Widgets ───────────────────────────────────────────────────────────

class _FeeCardShimmer extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor:      Colors.grey.shade200,
      highlightColor: Colors.grey.shade100,
      child: Container(
        height:  160,
        margin:  const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color:        Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }
}

class _NoBatchesState extends StatelessWidget {
  const _NoBatchesState();
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        children: [
          Icon(
            Icons.school_outlined,
            size:  56,
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.2),
          ),
          const SizedBox(height: 12),
          Text(
            'Not enrolled in any batch yet',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Your teacher will enroll you in a batch.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3),
            ),
          ),
        ],
      ),
    );
  }
}

class _BatchErrorState extends StatelessWidget {
  const _BatchErrorState({required this.onRetry});
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const Icon(Icons.wifi_off_rounded, size: 40, color: Colors.grey),
          const SizedBox(height: 8),
          const Text('Failed to load batches'),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}