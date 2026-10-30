/// features/teacher/presentation/pages/create_batch_page.dart
/// Batch creation form for teachers.
///
/// PRD Reference: Section 04 — Batch Creation Fields
///   1. Batch Name (string, required)
///   2. Start Date (date picker)
///   3. Batch Fee ₹ (integer, monthly)
///   4. Duration (years, integer)
///   5. Fees Time Limit (grace period in days)
///
/// After successful creation, navigates to batch detail page.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/providers/providers.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/batch_repository.dart';
import '../../../auth/presentation/widgets/auth_text_field.dart';

// ── Create Batch State ────────────────────────────────────────────────────────

class _CreateBatchState {
  const _CreateBatchState({
    this.isLoading    = false,
    this.errorMessage,
    this.selectedDate,
  });
  final bool      isLoading;
  final String?   errorMessage;
  final DateTime? selectedDate;

  _CreateBatchState copyWith({
    bool?     isLoading,
    String?   errorMessage,
    DateTime? selectedDate,
    bool      clearError = false,
  }) =>
      _CreateBatchState(
        isLoading:    isLoading    ?? this.isLoading,
        errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
        selectedDate: selectedDate ?? this.selectedDate,
      );
}

final _createBatchStateProvider =
    StateProvider<_CreateBatchState>((_) => const _CreateBatchState());

// ── Page ──────────────────────────────────────────────────────────────────────

class CreateBatchPage extends ConsumerStatefulWidget {
  const CreateBatchPage({super.key});

  @override
  ConsumerState<CreateBatchPage> createState() => _CreateBatchPageState();
}

class _CreateBatchPageState extends ConsumerState<CreateBatchPage> {
  final _formKey          = GlobalKey<FormState>();
  final _nameCtrl         = TextEditingController();
  final _feeCtrl          = TextEditingController();
  final _durationCtrl     = TextEditingController(text: '1');
  final _gracePeriodCtrl  = TextEditingController(text: '7');

  @override
  void dispose() {
    _nameCtrl.dispose();
    _feeCtrl.dispose();
    _durationCtrl.dispose();
    _gracePeriodCtrl.dispose();
    super.dispose();
  }

  // ── Date Picker ────────────────────────────────────────────────────────────
  Future<void> _pickDate() async {
    final now    = DateTime.now();
    final picked = await showDatePicker(
      context:        context,
      initialDate:    now,
      firstDate:      DateTime(now.year - 1),
      lastDate:       DateTime(now.year + 5),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: Theme.of(context).colorScheme.copyWith(
            primary: AppTheme.primaryTeal,
          ),
        ),
        child: child!,
      ),
    );

    if (picked != null) {
      ref.read(_createBatchStateProvider.notifier).update(
        (s) => s.copyWith(selectedDate: picked),
      );
    }
  }

  // ── Submit ─────────────────────────────────────────────────────────────────
  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final formState = ref.read(_createBatchStateProvider);

    if (formState.selectedDate == null) {
      ref.read(_createBatchStateProvider.notifier).update(
        (s) => s.copyWith(errorMessage: 'Please select a start date.'),
      );
      return;
    }

    ref.read(_createBatchStateProvider.notifier).update(
      (s) => s.copyWith(isLoading: true, clearError: true),
    );

    FocusScope.of(context).unfocus();

    final repo   = BatchRepository(apiClient: ref.read(apiClientProvider));
    final result = await repo.createBatch(
      name:            _nameCtrl.text.trim(),
      startDate:       DateFormat('yyyy-MM-dd').format(formState.selectedDate!),
      feeAmount:       int.parse(_feeCtrl.text.trim()),
      durationYears:   int.parse(_durationCtrl.text.trim()),
      gracePeriodDays: int.parse(_gracePeriodCtrl.text.trim()),
    );

    if (!mounted) return;

    if (result.isSuccess) {
      // Navigate to new batch detail
      context.go('/teacher/batch/${result.data!.id}');
    } else {
      ref.read(_createBatchStateProvider.notifier).update(
        (s) => s.copyWith(
          isLoading:    false,
          errorMessage: result.error,
        ),
      );
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final formState = ref.watch(_createBatchStateProvider);
    final theme     = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title:   const Text('Create New Batch'),
        leading: IconButton(
          icon:      const Icon(Icons.close_rounded),
          onPressed: () => context.go(AppConstants.routeTeacherHome),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppConstants.screenPadding),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

                // ── Section Title ─────────────────────────────────────────────
                _SectionLabel('Batch Information'),
                const SizedBox(height: 12),

                // ── 1. Batch Name ─────────────────────────────────────────────
                // PRD Section 04: "Batch Name (string, required)"
                AuthTextField(
                  controller:   _nameCtrl,
                  label:        'Batch Name',
                  hint:         'e.g. Class 10 Science — Batch A',
                  prefixIcon:   Icons.class_outlined,
                  textInputAction: TextInputAction.next,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Batch name is required';
                    }
                    if (v.trim().length < 2) return 'Name too short';
                    if (v.trim().length > 150) return 'Name too long (max 150)';
                    return null;
                  },
                ).animate().fadeIn(delay: 50.ms),

                const SizedBox(height: 16),

                // ── 2. Start Date ─────────────────────────────────────────────
                // PRD Section 04: "Start Date (date picker)"
                GestureDetector(
                  onTap: _pickDate,
                  child: AbsorbPointer(
                    child: TextFormField(
                      readOnly: true,
                      decoration: InputDecoration(
                        labelText: 'Start Date',
                        hintText:  'Select date',
                        prefixIcon: const Icon(
                          Icons.calendar_today_outlined,
                          size: 20,
                        ),
                        suffixIcon: const Icon(
                          Icons.arrow_drop_down_rounded,
                        ),
                      ),
                      controller: TextEditingController(
                        text: formState.selectedDate != null
                            ? DateFormat('dd MMM yyyy')
                                .format(formState.selectedDate!)
                            : '',
                      ),
                      validator: (_) {
                        if (formState.selectedDate == null) {
                          return 'Start date is required';
                        }
                        return null;
                      },
                    ),
                  ),
                ).animate().fadeIn(delay: 100.ms),

                const SizedBox(height: 24),

                _SectionLabel('Fee Configuration'),
                const SizedBox(height: 12),

                // ── 3. Batch Fee ──────────────────────────────────────────────
                // PRD Section 04: "Batch Fee ₹ (integer, monthly)"
                TextFormField(
                  controller:   _feeCtrl,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  decoration: const InputDecoration(
                    labelText:  'Monthly Fee (₹)',
                    hintText:   '1500',
                    prefixIcon: Icon(
                      Icons.currency_rupee_rounded,
                      size: 20,
                    ),
                    prefixText: '₹ ',
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Fee amount is required';
                    final n = int.tryParse(v);
                    if (n == null || n < 1) return 'Enter a valid fee amount';
                    if (n > 999999) return 'Amount too large';
                    return null;
                  },
                ).animate().fadeIn(delay: 150.ms),

                const SizedBox(height: 16),

                // ── 4 & 5: Duration + Grace Period (side by side) ─────────────
                Row(
                  children: [
                    // 4. Duration
                    // PRD Section 04: "Duration (years, integer)"
                    Expanded(
                      child: TextFormField(
                        controller:   _durationCtrl,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.next,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: const InputDecoration(
                          labelText:   'Duration (years)',
                          hintText:    '1',
                          prefixIcon:  Icon(
                            Icons.schedule_outlined,
                            size: 20,
                          ),
                          suffixText:  'yr',
                        ),
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'Required';
                          final n = int.tryParse(v);
                          if (n == null || n < 1) return 'Min 1 year';
                          if (n > 10) return 'Max 10 years';
                          return null;
                        },
                      ),
                    ),

                    const SizedBox(width: 12),

                    // 5. Grace Period
                    // PRD Section 04: "Fees Time Limit (grace period in days)"
                    Expanded(
                      child: TextFormField(
                        controller:   _gracePeriodCtrl,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.done,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: const InputDecoration(
                          labelText:  'Grace Period',
                          hintText:   '7',
                          prefixIcon: Icon(
                            Icons.hourglass_bottom_rounded,
                            size: 20,
                          ),
                          suffixText: 'days',
                        ),
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'Required';
                          final n = int.tryParse(v);
                          if (n == null || n < 1) return 'Min 1 day';
                          if (n > 28) return 'Max 28 days';
                          return null;
                        },
                      ),
                    ),
                  ],
                ).animate().fadeIn(delay: 200.ms),

                const SizedBox(height: 8),

                // Grace period helper text
                Text(
                  '💡 Students who haven\'t paid by day N of the month will '
                  'receive an overdue notification.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withOpacity(0.5),
                  ),
                ),

                const SizedBox(height: 28),

                // ── Error Banner ──────────────────────────────────────────────
                if (formState.errorMessage != null) ...[
                  Container(
                    width:   double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.errorRed.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: AppTheme.errorRed.withOpacity(0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.error_outline,
                          color: AppTheme.errorRed,
                          size:  18,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            formState.errorMessage!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: AppTheme.errorRed,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ).animate().fadeIn().shake(),
                  const SizedBox(height: 16),
                ],

                // ── Submit ────────────────────────────────────────────────────
                SizedBox(
                  width:  double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: formState.isLoading ? null : _submit,
                    child: formState.isLoading
                        ? const SizedBox(
                            width:  22,
                            height: 22,
                            child:  CircularProgressIndicator(
                              color:       Colors.white,
                              strokeWidth: 2.5,
                            ),
                          )
                        : const Text('Create Batch'),
                  ),
                ).animate().fadeIn(delay: 250.ms),

                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: Theme.of(context).textTheme.titleSmall?.copyWith(
      color:      AppTheme.primaryTeal,
      fontWeight: FontWeight.w700,
    ),
  );
}