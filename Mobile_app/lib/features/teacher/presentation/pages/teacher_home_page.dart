/// features/teacher/presentation/pages/teacher_home_page.dart
/// Teacher dashboard — lists all batches with summary stats.
///
/// PRD Reference: Section 02 — Teacher Role
///   "Create & manage batches"
///   "Mark student payments as paid"
///   "Administer group chats"
///
/// FEATURES:
///   - List of teacher's active batches (BatchCard widgets)
///   - Student count and fee summary per batch
///   - FAB to create new batch
///   - Pull-to-refresh
///   - Empty state when no batches exist

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:shimmer/shimmer.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/providers/providers.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../teacher/data/batch_repository.dart';
import '../widgets/batch_card.dart';

// ── Providers ─────────────────────────────────────────────────────────────────

final _batchRepositoryProvider = Provider<BatchRepository>((ref) {
  return BatchRepository(apiClient: ref.watch(apiClientProvider));
});

final _batchListProvider =
    FutureProvider.autoDispose<List<BatchModel>>((ref) async {
  final repo   = ref.watch(_batchRepositoryProvider);
  final result = await repo.listBatches();
  if (result.isSuccess) return result.data!;
  throw Exception(result.error);
});

// ── Page ──────────────────────────────────────────────────────────────────────

class TeacherHomePage extends ConsumerWidget {
  const TeacherHomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState   = ref.watch(authStateProvider);
    final batchAsync  = ref.watch(_batchListProvider);
    final theme       = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Hello, ${authState.userName?.split(' ').first ?? 'Teacher'} 👋',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              'Manage your batches',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.5),
              ),
            ),
          ],
        ),
        actions: [
          // Notification bell
          IconButton(
            icon:      const Icon(Icons.notifications_outlined),
            tooltip:   'Notifications',
            onPressed: () => context.go('/teacher/notifications'),
          ),
        ],
      ),

      // ── FAB: Create Batch ───────────────────────────────────────────────────
      floatingActionButton: FloatingActionButton.extended(
        onPressed:   () => context.go('/teacher/create-batch'),
        backgroundColor: AppTheme.primaryTeal,
        foregroundColor: Colors.white,
        icon:        const Icon(Icons.add_rounded),
        label:       const Text('New Batch'),
      ),

      body: RefreshIndicator(
        color:     AppTheme.primaryTeal,
        onRefresh: () => ref.refresh(_batchListProvider.future),
        child: batchAsync.when(
          loading: () => _LoadingShimmer(),
          error:   (err, _) => _ErrorState(
            message:   err.toString().replaceAll('Exception: ', ''),
            onRetry:   () => ref.invalidate(_batchListProvider),
          ),
          data: (batches) {
            if (batches.isEmpty) {
              return _EmptyState(
                onCreateBatch: () => context.go('/teacher/create-batch'),
              );
            }
            return _BatchList(batches: batches, ref: ref);
          },
        ),
      ),
    );
  }
}

// ── Batch List ────────────────────────────────────────────────────────────────

class _BatchList extends StatelessWidget {
  const _BatchList({required this.batches, required this.ref});
  final List<BatchModel> batches;
  final WidgetRef        ref;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        // ── Stats Header ──────────────────────────────────────────────────────
        SliverToBoxAdapter(
          child: _StatsHeader(batches: batches),
        ),

        SliverPadding(
          padding: const EdgeInsets.only(
            left:   16,
            right:  16,
            top:    8,
            bottom: 100, // FAB clearance
          ),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final batch = batches[index];
                return BatchCard(
                  batch:       batch,
                  onTap:       () => context.go('/teacher/batch/${batch.id}'),
                  onManageFees: () =>
                      context.go('/teacher/fees/${batch.id}'),
                  onOpenChat:   () => context.go(
                    '/chat/${batch.id}',
                    extra: {'name': batch.name},
                  ),
                ).animate(delay: (index * 60).ms).fadeIn().slideY(
                  begin: 0.15,
                  end:   0,
                );
              },
              childCount: batches.length,
            ),
          ),
        ),
      ],
    );
  }
}

// ── Stats Header ──────────────────────────────────────────────────────────────

class _StatsHeader extends StatelessWidget {
  const _StatsHeader({required this.batches});
  final List<BatchModel> batches;

  @override
  Widget build(BuildContext context) {
    final theme        = Theme.of(context);
    final totalStudents = batches.fold<int>(
      0, (sum, b) => sum + b.studentCount,
    );

    return Container(
      margin:  const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppTheme.primaryTeal, AppTheme.primaryTealLight],
          begin:  Alignment.topLeft,
          end:    Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color:      AppTheme.primaryTeal.withOpacity(0.25),
            blurRadius: 12,
            offset:     const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          _StatItem(
            value: '${batches.length}',
            label: 'Batches',
            icon:  Icons.class_outlined,
          ),
          const _Divider(),
          _StatItem(
            value: '$totalStudents',
            label: 'Students',
            icon:  Icons.people_outlined,
          ),
          const _Divider(),
          _StatItem(
            value: batches
                .where((b) => b.isActive)
                .length
                .toString(),
            label: 'Active',
            icon:  Icons.check_circle_outline,
          ),
        ],
      ),
    )
        .animate()
        .fadeIn(duration: 500.ms)
        .slideY(begin: -0.1, end: 0);
  }
}

class _StatItem extends StatelessWidget {
  const _StatItem({
    required this.value,
    required this.label,
    required this.icon,
  });
  final String   value;
  final String   label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, color: Colors.white70, size: 20),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize:   22,
              fontWeight: FontWeight.w700,
              color:      Colors.white,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize:   11,
              color:      Colors.white70,
            ),
          ),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();
  @override
  Widget build(BuildContext context) => Container(
    width:  1,
    height: 40,
    color:  Colors.white24,
    margin: const EdgeInsets.symmetric(horizontal: 8),
  );
}

// ── Empty State ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onCreateBatch});
  final VoidCallback onCreateBatch;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width:  96,
              height: 96,
              decoration: BoxDecoration(
                color:        AppTheme.primaryTeal.withOpacity(0.08),
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Icon(
                Icons.class_outlined,
                size:  48,
                color: AppTheme.primaryTeal,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'No batches yet',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Create your first batch to start managing\nstudents and fees.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.55),
              ),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: 200,
              child: ElevatedButton.icon(
                onPressed: onCreateBatch,
                icon:      const Icon(Icons.add_rounded, size: 18),
                label:     const Text('Create Batch'),
              ),
            ),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 600.ms);
  }
}

// ── Error State ───────────────────────────────────────────────────────────────

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});
  final String       message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.wifi_off_rounded,
              size:  64,
              color: theme.colorScheme.error.withOpacity(0.4),
            ),
            const SizedBox(height: 16),
            Text(
              'Failed to load batches',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.5),
              ),
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon:      const Icon(Icons.refresh_rounded),
              label:     const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Loading Shimmer ───────────────────────────────────────────────────────────

class _LoadingShimmer extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor:      Colors.grey.shade200,
      highlightColor: Colors.grey.shade100,
      child: ListView.builder(
        padding:     const EdgeInsets.all(16),
        itemCount:   4,
        itemBuilder: (_, __) => Container(
          height:      140,
          margin:      const EdgeInsets.only(bottom: 12),
          decoration:  BoxDecoration(
            color:        Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}