/// features/auth/presentation/pages/login_page.dart
/// Login screen for both teachers and students.
///
/// PRD Reference: Section 09 — POST /auth/login
/// PRD Reference: Section 11 — FCM Token Staleness
///   "Re-register token on every app launch" — sent with login payload.
///
/// FORM:
///   Email, Password (obscured), Login button
///   "Don't have an account? Register" link
///
/// POST-LOGIN:
///   AuthStateNotifier.onLoginSuccess() → GoRouter redirects to role home

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/providers/providers.dart';
import '../../../../core/theme/app_theme.dart';
import '../widgets/auth_text_field.dart';

// ── Login State ───────────────────────────────────────────────────────────────

class _LoginFormState {
  const _LoginFormState({
    this.isLoading    = false,
    this.errorMessage,
    this.obscurePassword = true,
  });

  final bool    isLoading;
  final String? errorMessage;
  final bool    obscurePassword;

  _LoginFormState copyWith({
    bool?   isLoading,
    String? errorMessage,
    bool?   obscurePassword,
    bool    clearError = false,
  }) =>
      _LoginFormState(
        isLoading:       isLoading       ?? this.isLoading,
        errorMessage:    clearError ? null : errorMessage ?? this.errorMessage,
        obscurePassword: obscurePassword ?? this.obscurePassword,
      );
}

final _loginFormProvider =
    StateProvider<_LoginFormState>((_) => const _LoginFormState());

// ── Login Page ────────────────────────────────────────────────────────────────

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _formKey       = GlobalKey<FormState>();
  final _emailCtrl     = TextEditingController();
  final _passwordCtrl  = TextEditingController();
  final _emailFocus    = FocusNode();
  final _passwordFocus = FocusNode();

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  // ── Submit ──────────────────────────────────────────────────────────────────
  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    ref.read(_loginFormProvider.notifier).update(
      (s) => s.copyWith(isLoading: true, clearError: true),
    );

    FocusScope.of(context).unfocus();

    final authRepo = ref.read(authRepositoryProvider);
    final result   = await authRepo.login(
      email:    _emailCtrl.text.trim(),
      password: _passwordCtrl.text,
    );

    if (!mounted) return;

    if (result.isSuccess) {
      final data   = result.data!;
      final tokens = data.tokens;
      final user   = data.user;

      // Transition auth state — GoRouter handles navigation
      await ref.read(authStateProvider.notifier).onLoginSuccess(
        userId:       user.id,
        userName:     user.name,
        userEmail:    user.email,
        role:         user.role,
        accessToken:  tokens.accessToken,
        refreshToken: tokens.refreshToken,
        refreshExpiry: tokens.refreshTokenExpires,
      );
    } else {
      ref.read(_loginFormProvider.notifier).update(
        (s) => s.copyWith(
          isLoading:    false,
          errorMessage: result.error,
        ),
      );
    }
  }

  // ── Build ───────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final formState  = ref.watch(_loginFormProvider);
    final theme      = Theme.of(context);
    final size       = MediaQuery.sizeOf(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
            horizontal: AppConstants.screenPadding,
            vertical:   32,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: size.height - 100),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment:  MainAxisAlignment.center,
              children: [

                // ── Header ───────────────────────────────────────────────────
                const SizedBox(height: 24),

                Container(
                  width:  56,
                  height: 56,
                  decoration: BoxDecoration(
                    color:        AppTheme.primaryTeal,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(
                    Icons.school_rounded,
                    color: Colors.white,
                    size:  30,
                  ),
                ).animate().fadeIn(duration: 500.ms),

                const SizedBox(height: 24),

                Text(
                  'Welcome back',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ).animate(delay: 100.ms).fadeIn().slideX(begin: -0.1),

                const SizedBox(height: 6),

                Text(
                  'Sign in to your EduPay account',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurface.withOpacity(0.6),
                  ),
                ).animate(delay: 150.ms).fadeIn(),

                const SizedBox(height: 40),

                // ── Form ──────────────────────────────────────────────────────
                Form(
                  key: _formKey,
                  child: Column(
                    children: [

                      // Email
                      AuthTextField(
                        controller:  _emailCtrl,
                        focusNode:   _emailFocus,
                        label:       'Email Address',
                        hint:        'you@example.com',
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        prefixIcon:  Icons.email_outlined,
                        onFieldSubmitted: (_) =>
                            FocusScope.of(context).requestFocus(_passwordFocus),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) {
                            return 'Email is required';
                          }
                          if (!RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(v)) {
                            return 'Enter a valid email address';
                          }
                          return null;
                        },
                      ).animate(delay: 200.ms).fadeIn().slideY(begin: 0.2),

                      const SizedBox(height: 16),

                      // Password
                      AuthTextField(
                        controller:      _passwordCtrl,
                        focusNode:       _passwordFocus,
                        label:           'Password',
                        hint:            '••••••••',
                        obscureText:     formState.obscurePassword,
                        textInputAction: TextInputAction.done,
                        prefixIcon:      Icons.lock_outline_rounded,
                        onFieldSubmitted: (_) => _submit(),
                        suffixIcon: IconButton(
                          icon: Icon(
                            formState.obscurePassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                            size: 20,
                          ),
                          onPressed: () {
                            ref.read(_loginFormProvider.notifier).update(
                              (s) => s.copyWith(
                                obscurePassword: !s.obscurePassword,
                              ),
                            );
                          },
                        ),
                        validator: (v) {
                          if (v == null || v.isEmpty) {
                            return 'Password is required';
                          }
                          return null;
                        },
                      ).animate(delay: 250.ms).fadeIn().slideY(begin: 0.2),

                      const SizedBox(height: 24),

                      // Error Banner
                      if (formState.errorMessage != null) ...[
                        Container(
                          width:   double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color:        AppTheme.errorRed.withOpacity(0.08),
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

                      // Login Button
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
                              : const Text('Sign In'),
                        ),
                      ).animate(delay: 300.ms).fadeIn(),

                      const SizedBox(height: 16),

                      // Register Link
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            "Don't have an account? ",
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurface.withOpacity(0.6),
                            ),
                          ),
                          TextButton(
                            onPressed: () =>
                                context.go(AppConstants.routeRegister),
                            style: TextButton.styleFrom(
                              padding:        EdgeInsets.zero,
                              minimumSize:    const Size(0, 0),
                              tapTargetSize:  MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: const Text('Register'),
                          ),
                        ],
                      ).animate(delay: 350.ms).fadeIn(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}