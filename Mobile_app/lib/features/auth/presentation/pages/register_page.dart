/// features/auth/presentation/pages/register_page.dart
/// Registration screen for new teachers and students.
///
/// PRD Reference: Section 09 — POST /auth/register
/// PRD Reference: Section 02 — User Roles
///   Role selector: Teacher | Student
///
/// FORM FIELDS:
///   Full Name, Email, Password, Confirm Password, Role Selector
///
/// VALIDATION:
///   All fields validated client-side before API call.
///   Server-side validation errors displayed as banner.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/providers/providers.dart';
import '../../../../core/theme/app_theme.dart';
import '../widgets/auth_text_field.dart';
import '../widgets/role_selector.dart';

// ── Register State ────────────────────────────────────────────────────────────
class _RegisterState {
  const _RegisterState({
    this.isLoading       = false,
    this.errorMessage,
    this.selectedRole    = AppConstants.roleStudent,
    this.obscurePassword = true,
    this.obscureConfirm  = true,
  });

  final bool    isLoading;
  final String? errorMessage;
  final String  selectedRole;
  final bool    obscurePassword;
  final bool    obscureConfirm;

  _RegisterState copyWith({
    bool?   isLoading,
    String? errorMessage,
    String? selectedRole,
    bool?   obscurePassword,
    bool?   obscureConfirm,
    bool    clearError = false,
  }) =>
      _RegisterState(
        isLoading:       isLoading       ?? this.isLoading,
        errorMessage:    clearError ? null : errorMessage ?? this.errorMessage,
        selectedRole:    selectedRole    ?? this.selectedRole,
        obscurePassword: obscurePassword ?? this.obscurePassword,
        obscureConfirm:  obscureConfirm  ?? this.obscureConfirm,
      );
}

final _registerStateProvider =
    StateProvider<_RegisterState>((_) => const _RegisterState());

// ── Register Page ─────────────────────────────────────────────────────────────
class RegisterPage extends ConsumerStatefulWidget {
  const RegisterPage({super.key});

  @override
  ConsumerState<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends ConsumerState<RegisterPage> {
  final _formKey       = GlobalKey<FormState>();
  final _nameCtrl      = TextEditingController();
  final _emailCtrl     = TextEditingController();
  final _passwordCtrl  = TextEditingController();
  final _confirmCtrl   = TextEditingController();

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final formState = ref.read(_registerStateProvider);

    ref.read(_registerStateProvider.notifier).update(
      (s) => s.copyWith(isLoading: true, clearError: true),
    );

    FocusScope.of(context).unfocus();

    final authRepo = ref.read(authRepositoryProvider);
    final result   = await authRepo.register(
      name:     _nameCtrl.text.trim(),
      email:    _emailCtrl.text.trim(),
      password: _passwordCtrl.text,
      role:     formState.selectedRole,
    );

    if (!mounted) return;

    if (result.isSuccess) {
      final data = result.data!;
      await ref.read(authStateProvider.notifier).onLoginSuccess(
        userId:        data.user.id,
        userName:      data.user.name,
        userEmail:     data.user.email,
        role:          data.user.role,
        accessToken:   data.tokens.accessToken,
        refreshToken:  data.tokens.refreshToken,
        refreshExpiry: data.tokens.refreshTokenExpires,
      );
    } else {
      ref.read(_registerStateProvider.notifier).update(
        (s) => s.copyWith(isLoading: false, errorMessage: result.error),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final formState = ref.watch(_registerStateProvider);
    final theme     = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title:           const Text('Create Account'),
        leading: IconButton(
          icon:      const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.go(AppConstants.routeLogin),
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

                const SizedBox(height: 8),

                Text(
                  'Join EduPay',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ).animate().fadeIn(),

                const SizedBox(height: 4),

                Text(
                  'Create your account to get started',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withOpacity(0.6),
                  ),
                ).animate(delay: 50.ms).fadeIn(),

                const SizedBox(height: 28),

                // ── Role Selector ─────────────────────────────────────────────
                // PRD Section 02: Teacher or Student role selection
                Text(
                  'I am a...',
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 10),

                RoleSelector(
                  selectedRole: formState.selectedRole,
                  onRoleSelected: (role) {
                    ref.read(_registerStateProvider.notifier).update(
                      (s) => s.copyWith(selectedRole: role),
                    );
                  },
                ).animate(delay: 100.ms).fadeIn(),

                const SizedBox(height: 20),

                // ── Full Name ─────────────────────────────────────────────────
                AuthTextField(
                  controller:      _nameCtrl,
                  label:           'Full Name',
                  hint:            'Rajesh Kumar',
                  prefixIcon:      Icons.person_outline,
                  textInputAction: TextInputAction.next,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Name is required';
                    if (v.trim().length < 2) return 'Name too short';
                    return null;
                  },
                ).animate(delay: 150.ms).fadeIn(),

                const SizedBox(height: 16),

                // ── Email ─────────────────────────────────────────────────────
                AuthTextField(
                  controller:      _emailCtrl,
                  label:           'Email Address',
                  hint:            'you@example.com',
                  prefixIcon:      Icons.email_outlined,
                  keyboardType:    TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Email is required';
                    if (!RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(v.trim())) {
                      return 'Enter a valid email';
                    }
                    return null;
                  },
                ).animate(delay: 200.ms).fadeIn(),

                const SizedBox(height: 16),

                // ── Password ──────────────────────────────────────────────────
                AuthTextField(
                  controller:      _passwordCtrl,
                  label:           'Password',
                  hint:            '••••••••',
                  prefixIcon:      Icons.lock_outline_rounded,
                  obscureText:     formState.obscurePassword,
                  textInputAction: TextInputAction.next,
                  suffixIcon: IconButton(
                    icon: Icon(
                      formState.obscurePassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      size: 20,
                    ),
                    onPressed: () {
                      ref.read(_registerStateProvider.notifier).update(
                        (s) => s.copyWith(
                          obscurePassword: !s.obscurePassword,
                        ),
                      );
                    },
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Password is required';
                    if (v.length < 8) return 'Minimum 8 characters';
                    if (!v.contains(RegExp(r'[A-Z]'))) {
                      return 'Include at least one uppercase letter';
                    }
                    if (!v.contains(RegExp(r'[0-9]'))) {
                      return 'Include at least one number';
                    }
                    return null;
                  },
                ).animate(delay: 250.ms).fadeIn(),

                const SizedBox(height: 16),

                // ── Confirm Password ──────────────────────────────────────────
                AuthTextField(
                  controller:      _confirmCtrl,
                  label:           'Confirm Password',
                  hint:            '••••••••',
                  prefixIcon:      Icons.lock_outline_rounded,
                  obscureText:     formState.obscureConfirm,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _submit(),
                  suffixIcon: IconButton(
                    icon: Icon(
                      formState.obscureConfirm
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      size: 20,
                    ),
                    onPressed: () {
                      ref.read(_registerStateProvider.notifier).update(
                        (s) => s.copyWith(obscureConfirm: !s.obscureConfirm),
                      );
                    },
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Please confirm password';
                    if (v != _passwordCtrl.text) return 'Passwords do not match';
                    return null;
                  },
                ).animate(delay: 300.ms).fadeIn(),

                const SizedBox(height: 24),

                // ── Error Banner ──────────────────────────────────────────────
                if (formState.errorMessage != null) ...[
                  Container(
                    width:   double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color:  AppTheme.errorRed.withOpacity(0.08),
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

                // ── Submit Button ─────────────────────────────────────────────
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
                        : const Text('Create Account'),
                  ),
                ).animate(delay: 350.ms).fadeIn(),

                const SizedBox(height: 16),

                // ── Login Link ────────────────────────────────────────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Already have an account? ',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurface.withOpacity(0.6),
                      ),
                    ),
                    TextButton(
                      onPressed: () => context.go(AppConstants.routeLogin),
                      style: TextButton.styleFrom(
                        padding:       EdgeInsets.zero,
                        minimumSize:   const Size(0, 0),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text('Sign In'),
                    ),
                  ],
                ).animate(delay: 400.ms).fadeIn(),

                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}