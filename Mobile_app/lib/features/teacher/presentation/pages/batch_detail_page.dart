/// features/teacher/presentation/pages/batch_detail_page.dart
/// Batch detail screen showing students, fee summary, and quick actions.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/providers/providers.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/batch_repository.dart';

// ── Providers ─────────────────────────────────────────────────────────────────

final _batchRepositoryProvider = Provider<BatchRepository>((ref) {
  return BatchRepository(apiClient: ref.watch(apiClientProvider));
});

final _batchDetailProvider =
    FutureProvider.autoDispose.family<BatchModel, String>((ref, batchId) async {
  final repo   = ref.watch(_batchRepositoryProvider);
  final result = await repo.getBatchById(batchId);
  if (result.isSuccess) return result.data!;
  throw Exception(result.error);
});

// ── Page ──────────────────────────────────────────────────────────────────────

class BatchDetailPage extends ConsumerStatefulWidget {
  const BatchDetailPage({super.key, required this.batchId});
  final String batchId;

  @override
  ConsumerState<BatchDetailPage> createState() => _BatchDetailPageState();
}

class _BatchDetailPageState extends ConsumerState<BatchDetailPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // ── Show Enroll Bottom Sheet ───────────────────────────────────────────────
  Future<void> _showEnrollDialog(BuildContext context) async {
    await showModalBottomSheet(
      context:            context,
      isScrollControlled: true,
      backgroundColor:    Colors.transparent,
      builder: (ctx) => _EnrollBottomSheet(
        batchId:   widget.batchId,
        onEnrolled: () {
          ref.invalidate(_batchDetailProvider(widget.batchId));
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content:         Text('Student enrolled successfully!'),
                backgroundColor: AppTheme.successGreen,
              ),
            );
          }
        },
      ),
    );
  }

  // ── Remove Student ─────────────────────────────────────────────────────────
  Future<void> _removeStudent(
    BuildContext context,
    StudentModel student,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title:   const Text('Remove Student'),
        content: Text(
          'Remove ${student.name} from this batch?\n\n'
          'Their fee history will be preserved.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child:     const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
              foregroundColor: AppTheme.errorRed,
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final repo   = ref.read(_batchRepositoryProvider);
    final result = await repo.removeStudent(
      batchId:   widget.batchId,
      studentId: student.id,
    );

    if (!mounted) return;

    if (result.isSuccess) {
      ref.invalidate(_batchDetailProvider(widget.batchId));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${student.name} removed from batch.')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:         Text(result.error ?? 'Removal failed'),
          backgroundColor: AppTheme.errorRed,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final batchAsync = ref.watch(_batchDetailProvider(widget.batchId));
    final theme      = Theme.of(context);

    return Scaffold(
      body: batchAsync.when(
        loading: () => const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
        error: (err, _) => Scaffold(
          appBar: AppBar(title: const Text('Batch Detail')),
          body: Center(
            child: Text(err.toString().replaceAll('Exception: ', '')),
          ),
        ),
        data: (batch) => NestedScrollView(
          headerSliverBuilder: (context, _) => [
            // ── Sliver App Bar ──────────────────────────────────────────────
            SliverAppBar(
              expandedHeight: 180,
              pinned:         true,
              flexibleSpace: FlexibleSpaceBar(
                background: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppTheme.primaryTeal,
                        AppTheme.primaryTealLight,
                      ],
                      begin: Alignment.topLeft,
                      end:   Alignment.bottomRight,
                    ),
                  ),
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 56, 20, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment:  MainAxisAlignment.end,
                        children: [
                          Text(
                            batch.name,
                            style: const TextStyle(
                              fontFamily: 'Inter',
                              fontSize:   22,
                              fontWeight: FontWeight.w700,
                              color:      Colors.white,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${batch.studentCount} students  •  '
                            '₹${NumberFormat('#,##,###').format(batch.feeAmount)}/month  •  '
                            '${batch.durationYears} yr',
                            style: const TextStyle(
                              fontFamily: 'Inter',
                              fontSize:   13,
                              color:      Colors.white70,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              actions: [
                IconButton(
                  icon:    const Icon(
                    Icons.chat_outlined,
                    color: Colors.white,
                  ),
                  tooltip:  'Open Chat',
                  onPressed: () => context.go(
                    '/chat/${batch.id}',
                    extra: {'name': batch.name},
                  ),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.account_balance_wallet_outlined,
                    color: Colors.white,
                  ),
                  tooltip:  'Manage Fees',
                  onPressed: () =>
                      context.go('/teacher/fees/${batch.id}'),
                ),
              ],
            ),

            // ── Tab Bar ────────────────────────────────────────────────────
            SliverPersistentHeader(
              pinned:   true,
              delegate: _StickyTabBarDelegate(
                TabBar(
                  controller: _tabController,
                  indicatorColor:       AppTheme.primaryTeal,
                  labelColor:           AppTheme.primaryTeal,
                  unselectedLabelColor: theme.colorScheme.onSurface
                      .withValues(alpha: 0.5),
                  tabs: const [
                    Tab(text: 'Students'),
                    Tab(text: 'About'),
                  ],
                ),
              ),
            ),
          ],

          // ── Tab Views ──────────────────────────────────────────────────
          body: TabBarView(
            controller: _tabController,
            children: [
              _StudentsTab(
                students: batch.students,
                onRemove: (s) => _removeStudent(context, s),
                onEnroll: () => _showEnrollDialog(context),
              ),
              _AboutTab(batch: batch),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Enroll Bottom Sheet ───────────────────────────────────────────────────────
// Opens immediately with ALL non-enrolled students loaded.
// Search filters the list locally — no extra API calls on keystroke.

class _EnrollBottomSheet extends ConsumerStatefulWidget {
  const _EnrollBottomSheet({
    required this.batchId,
    required this.onEnrolled,
  });

  final String       batchId;
  final VoidCallback onEnrolled;

  @override
  ConsumerState<_EnrollBottomSheet> createState() =>
      _EnrollBottomSheetState();
}

class _EnrollBottomSheetState extends ConsumerState<_EnrollBottomSheet> {
  final _searchCtrl  = TextEditingController();
  final _searchFocus = FocusNode();

  // ── State ──────────────────────────────────────────────────────────────────
  List<StudentSearchResult> _allStudents      = [];
  List<StudentSearchResult> _filteredStudents = [];
  Set<String>               _enrollingIds     = {};
  bool                      _isLoadingAll     = true;
  String?                   _loadError;

  @override
  void initState() {
    super.initState();
    // Load ALL non-enrolled students when sheet opens
    _loadAllStudents();
    // Auto-focus search field
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  // ── Load ALL non-enrolled students from server ─────────────────────────────
  Future<void> _loadAllStudents() async {
    setState(() {
      _isLoadingAll = true;
      _loadError    = null;
    });

    final repo   = ref.read(_batchRepositoryProvider);
    final result = await repo.searchStudents(
      batchId: widget.batchId,
      name:    '', // empty = return ALL students
    );

    if (!mounted) return;

    if (result.isSuccess) {
      setState(() {
        _allStudents      = result.data!;
        _filteredStudents = List.from(_allStudents);
        _isLoadingAll     = false;
      });
    } else {
      setState(() {
        _isLoadingAll = false;
        _loadError    = result.error;
      });
    }
  }

  // ── Local filter — instant, no API call ───────────────────────────────────
  void _onSearchChanged(String value) {
    final query = value.trim().toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredStudents = List.from(_allStudents);
      } else {
        _filteredStudents = _allStudents.where((s) {
          return s.name.toLowerCase().contains(query) ||
                 s.email.toLowerCase().contains(query);
        }).toList();
      }
    });
  }

  // ── Enroll a student ───────────────────────────────────────────────────────
  Future<void> _enroll(StudentSearchResult student) async {
    setState(() => _enrollingIds.add(student.id));

    final repo   = ref.read(_batchRepositoryProvider);
    final result = await repo.enrollStudent(
      batchId:   widget.batchId,
      studentId: student.id,
    );

    if (!mounted) return;

    if (result.isSuccess) {
      setState(() {
        _enrollingIds.remove(student.id);
        // Remove from both lists — can't enroll same student twice
        _allStudents.removeWhere((s) => s.id == student.id);
        _filteredStudents.removeWhere((s) => s.id == student.id);
      });
      widget.onEnrolled();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:         Text('${student.name} enrolled!'),
          backgroundColor: AppTheme.successGreen,
          duration:        const Duration(seconds: 2),
        ),
      );
    } else {
      setState(() => _enrollingIds.remove(student.id));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:         Text(result.error ?? 'Enrollment failed'),
          backgroundColor: AppTheme.errorRed,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme      = Theme.of(context);
    final isDark     = theme.brightness == Brightness.dark;
    final sheetColor = isDark
        ? const Color(0xFF1E2A38)
        : Colors.white;

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize:     0.5,
      maxChildSize:     0.95,
      expand:           false,
      builder: (context, scrollController) => Container(
        decoration: BoxDecoration(
          color:        sheetColor,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(24),
          ),
        ),
        child: Column(
          children: [
            // ── Drag Handle ───────────────────────────────────────────────
            const SizedBox(height: 12),
            Container(
              width:  40,
              height: 4,
              decoration: BoxDecoration(
                color:        theme.colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),

            // ── Header ────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Container(
                    width:  40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppTheme.primaryTeal.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.person_add_outlined,
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
                          'Enroll Student',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          _isLoadingAll
                              ? 'Loading students…'
                              : '${_allStudents.length} student'
                                '${_allStudents.length == 1 ? '' : 's'}'
                                ' available',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.55),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // ── Search Field ──────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                controller:      _searchCtrl,
                focusNode:       _searchFocus,
                onChanged:       _onSearchChanged,
                textInputAction: TextInputAction.search,
                enabled:         !_isLoadingAll,
                decoration: InputDecoration(
                  hintText:   'Search by name or email…',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _searchCtrl.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded),
                          onPressed: () {
                            _searchCtrl.clear();
                            _onSearchChanged('');
                          },
                        )
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                      color: theme.colorScheme.outlineVariant,
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                      color: theme.colorScheme.outlineVariant,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(
                      color: AppTheme.primaryTeal,
                      width: 2,
                    ),
                  ),
                  filled:         true,
                  fillColor:      theme.colorScheme.surface,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical:   14,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 8),

            // ── Result Count ──────────────────────────────────────────────
            if (!_isLoadingAll && _loadError == null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
                child: Row(
                  children: [
                    Text(
                      _searchCtrl.text.trim().isEmpty
                          ? 'All students'
                          : '${_filteredStudents.length} result'
                            '${_filteredStudents.length == 1 ? '' : 's'}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurface
                            .withValues(alpha: 0.5),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),

            Divider(
              height: 1,
              color:  theme.colorScheme.outlineVariant
                  .withValues(alpha: 0.5),
            ),

            // ── List Body ─────────────────────────────────────────────────
            Expanded(
              child: _buildBody(theme, scrollController),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(ThemeData theme, ScrollController scrollController) {
    // ── Loading skeleton ───────────────────────────────────────────────────
    if (_isLoadingAll) {
      return _LoadingSkeleton();
    }

    // ── Error state with retry ─────────────────────────────────────────────
    if (_loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline_rounded,
                size:  52,
                color: AppTheme.errorRed.withValues(alpha: 0.7),
              ),
              const SizedBox(height: 12),
              Text(
                _loadError!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppTheme.errorRed,
                ),
              ),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: _loadAllStudents,
                icon:      const Icon(Icons.refresh_rounded),
                label:     const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    // ── No students in system ──────────────────────────────────────────────
    if (_allStudents.isEmpty && _searchCtrl.text.isEmpty) {
      return const _EmptyHint(
        icon:    Icons.people_outline_rounded,
        message: 'No students registered\nin the system yet',
      );
    }

    // ── No search results ──────────────────────────────────────────────────
    if (_filteredStudents.isEmpty) {
      return _EmptyHint(
        icon:    Icons.person_search_outlined,
        message: 'No students match\n"${_searchCtrl.text.trim()}"',
      );
    }

    // ── Student list ───────────────────────────────────────────────────────
    return ListView.separated(
      controller:       scrollController,
      padding:          const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount:        _filteredStudents.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final student     = _filteredStudents[index];
        final isEnrolling = _enrollingIds.contains(student.id);

        return _StudentResultTile(
          student:     student,
          isEnrolling: isEnrolling,
          onEnroll:    () => _enroll(student),
        )
            .animate(delay: (index * 30).ms)
            .fadeIn()
            .slideY(begin: 0.08, end: 0);
      },
    );
  }
}

// ── Loading Skeleton ──────────────────────────────────────────────────────────

class _LoadingSkeleton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme  = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final base   = isDark
        ? const Color(0xFF263238)
        : const Color(0xFFECEFF1);
    final shine  = isDark
        ? Colors.white.withValues(alpha: 0.04)
        : Colors.white.withValues(alpha: 0.6);

    return ListView.separated(
      padding:          const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount:        6,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, index) => Container(
        height: 76,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color:        base,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            // Avatar placeholder
            Container(
              width:  44,
              height: 44,
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF37474F)
                    : const Color(0xFFCFD8DC),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 12),
            // Text placeholders
            Expanded(
              child: Column(
                mainAxisAlignment:  MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 12,
                    width:  130,
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF37474F)
                          : const Color(0xFFCFD8DC),
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    height: 10,
                    width:  190,
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF37474F)
                          : const Color(0xFFCFD8DC),
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ],
              ),
            ),
            // Button placeholder
            Container(
              width:  100,
              height: 36,
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF37474F)
                    : const Color(0xFFCFD8DC),
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ],
        ),
      )
          .animate(onPlay: (c) => c.repeat())
          .shimmer(duration: const Duration(milliseconds: 1200), color: shine),
    );
  }
}

// ── Empty / Hint Widget ───────────────────────────────────────────────────────

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({
    required this.icon,
    required this.message,
    this.isError = false,
  });

  final IconData icon;
  final String   message;
  final bool     isError;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = isError
        ? AppTheme.errorRed
        : theme.colorScheme.onSurface.withValues(alpha: 0.3);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 52, color: color),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: color),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Student Result Tile ───────────────────────────────────────────────────────

class _StudentResultTile extends StatelessWidget {
  const _StudentResultTile({
    required this.student,
    required this.isEnrolling,
    required this.onEnroll,
  });

  final StudentSearchResult student;
  final bool                isEnrolling;
  final VoidCallback        onEnroll;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color:        theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.7),
        ),
        boxShadow: [
          BoxShadow(
            color:      Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset:     const Offset(0, 2),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
        leading: CircleAvatar(
          radius:          22,
          backgroundColor: AppTheme.primaryTeal.withValues(alpha: 0.12),
          child: Text(
            student.name.isNotEmpty
                ? student.name[0].toUpperCase()
                : '?',
            style: const TextStyle(
              color:      AppTheme.primaryTeal,
              fontWeight: FontWeight.w700,
              fontSize:   16,
            ),
          ),
        ),
        title: Text(
          student.name,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          student.email,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: SizedBox(
          width: 120,
          child: isEnrolling
              ? const Center(
                  child: SizedBox(
                    width:  22,
                    height: 22,
                    child:  CircularProgressIndicator(strokeWidth: 2.5),
                  ),
                )
              : FilledButton.icon(
                  onPressed: onEnroll,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primaryTeal,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical:    8,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    textStyle: const TextStyle(
                      fontSize:   12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  icon:  const Icon(Icons.person_add_rounded, size: 14),
                  label: const Text('Add Student'),
                ),
        ),
      ),
    );
  }
}

// ── Students Tab ──────────────────────────────────────────────────────────────

class _StudentsTab extends StatelessWidget {
  const _StudentsTab({
    required this.students,
    required this.onRemove,
    required this.onEnroll,
  });

  final List<StudentModel>          students;
  final void Function(StudentModel) onRemove;
  final VoidCallback                onEnroll;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        // ── Enroll Button ────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: OutlinedButton.icon(
            onPressed: onEnroll,
            icon:      const Icon(Icons.person_add_outlined, size: 18),
            label:     const Text('Enroll Student'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 44),
            ),
          ),
        ),

        if (students.isEmpty)
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.people_outline,
                    size:  56,
                    color: theme.colorScheme.onSurface
                        .withValues(alpha: 0.2),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No students enrolled yet',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface
                          .withValues(alpha: 0.4),
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          Expanded(
            child: ListView.separated(
              padding:          const EdgeInsets.all(16),
              itemCount:        students.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final student = students[index];
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical:    8,
                  ),
                  tileColor: theme.colorScheme.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: theme.colorScheme.outlineVariant,
                    ),
                  ),
                  leading: CircleAvatar(
                    backgroundColor:
                        AppTheme.primaryTeal.withValues(alpha: 0.1),
                    child: Text(
                      student.name[0].toUpperCase(),
                      style: const TextStyle(
                        color:      AppTheme.primaryTeal,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  title: Text(
                    student.name,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    student.email,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface
                          .withValues(alpha: 0.5),
                    ),
                  ),
                  trailing: IconButton(
                    icon:    const Icon(Icons.remove_circle_outline),
                    color:   AppTheme.errorRed,
                    tooltip: 'Remove student',
                    onPressed: () => onRemove(student),
                  ),
                ).animate(delay: (index * 40).ms).fadeIn();
              },
            ),
          ),
      ],
    );
  }
}

// ── About Tab ─────────────────────────────────────────────────────────────────

class _AboutTab extends StatelessWidget {
  const _AboutTab({required this.batch});
  final BatchModel batch;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final items = [
      _AboutItem(
        icon:  Icons.calendar_today_outlined,
        label: 'Start Date',
        value: DateFormat('dd MMM yyyy').format(
          DateTime.parse(batch.startDate),
        ),
      ),
      _AboutItem(
        icon:  Icons.currency_rupee_rounded,
        label: 'Monthly Fee',
        value: '₹${NumberFormat('#,##,###').format(batch.feeAmount)}',
      ),
      _AboutItem(
        icon:  Icons.schedule_outlined,
        label: 'Duration',
        value: '${batch.durationYears} year'
               '${batch.durationYears > 1 ? 's' : ''}',
      ),
      _AboutItem(
        icon:  Icons.hourglass_bottom_rounded,
        label: 'Grace Period',
        value: '${batch.gracePeriodDays} day'
               '${batch.gracePeriodDays > 1 ? 's' : ''}',
      ),
      _AboutItem(
        icon:  Icons.people_outlined,
        label: 'Students',
        value: '${batch.studentCount}',
      ),
    ];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: items.asMap().entries.map((e) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color:        theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: theme.colorScheme.outlineVariant,
            ),
          ),
          child: Row(
            children: [
              Icon(
                e.value.icon,
                size:  20,
                color: AppTheme.primaryTeal,
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    e.value.label,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurface
                          .withValues(alpha: 0.5),
                    ),
                  ),
                  Text(
                    e.value.value,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ).animate(delay: (e.key * 50).ms).fadeIn(),
      )).toList(),
    );
  }
}

class _AboutItem {
  const _AboutItem({
    required this.icon,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final String   label;
  final String   value;
}

// ── Sticky Tab Bar Delegate ───────────────────────────────────────────────────

class _StickyTabBarDelegate extends SliverPersistentHeaderDelegate {
  const _StickyTabBarDelegate(this.tabBar);
  final TabBar tabBar;

  @override
  double get minExtent => tabBar.preferredSize.height;
  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) =>
      Container(
        color: Theme.of(context).colorScheme.surface,
        child: tabBar,
      );

  @override
  bool shouldRebuild(_StickyTabBarDelegate old) => tabBar != old.tabBar;
}