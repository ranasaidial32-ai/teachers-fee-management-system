/// features/auth/presentation/pages/splash_page.dart
/// App launch splash screen — waits for auth state then navigates.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/providers/providers.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/auth_state.dart';

class SplashPage extends ConsumerStatefulWidget {
  const SplashPage({super.key});

  @override
  ConsumerState<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends ConsumerState<SplashPage> {
  // ── FIX: Single navigation flag prevents duplicate go() calls ──────────────
  bool _navigated = false;

  // ── FIX: Safety fallback — if auth hangs for >5s, force navigation ─────────
  Timer? _fallbackTimer;

  @override
  void initState() {
    super.initState();

    // Check if auth is already resolved synchronously (e.g. hot restart)
    final currentState = ref.read(authStateProvider);
    if (currentState.status != AuthStatus.initial &&
        currentState.status != AuthStatus.loading) {
      // Already resolved — schedule navigation on next frame
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _navigate(currentState);
      });
      return;
    }

    // Start fallback timer — if auth takes >5s something is wrong
    _fallbackTimer = Timer(const Duration(seconds: 5), () {
      debugPrint('Splash: ⚠ fallback timer fired — forcing unauthenticated');
      if (!_navigated && mounted) {
        _navigate(AuthState.unauthenticated());
      }
    });
  }

  // ── Navigate based on resolved auth state ───────────────────────────────────
  void _navigate(AuthState authState) {
    // Guard: only navigate once, and only if widget is still mounted
    if (_navigated || !mounted) return;
    _navigated = true;
    _fallbackTimer?.cancel();

    debugPrint(
      'Splash: navigating — status=${authState.status}, '
      'role=${authState.role}',
    );

    // ── FIX: addPostFrameCallback ensures the widget tree (including      ──
    // GoRouter) has finished its current build cycle before we call go().  
    // Calling context.go() mid-build causes "Navigator operation requested  
    // with a context that does not include a Navigator" errors.            
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      try {
        if (authState.isAuthenticated) {
          final destination = authState.isTeacher
              ? AppConstants.routeTeacherHome
              : AppConstants.routeStudentHome;
          context.go(destination);
        } else {
          // unauthenticated, error, or any unexpected state → login
          context.go(AppConstants.routeLogin);
        }
      } catch (e) {
        debugPrint('Splash: navigation error — $e');
        // Ultimate fallback
        if (mounted) context.go(AppConstants.routeLogin);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // ── FIX: ref.listen fires every time authStateProvider changes.        ──
    // We react to the transition OUT of initial/loading state and call     
    // _navigate exactly once. The _navigated flag prevents double-calls    
    // if both the listener and the fallback timer fire simultaneously.     
    ref.listen<AuthState>(authStateProvider, (previous, next) {
      debugPrint(
        'Splash: auth state changed — '
        '${previous?.status} → ${next.status}',
      );

      // Only act when auth has finished resolving
      if (next.status == AuthStatus.initial ||
          next.status == AuthStatus.loading) {
        return;
      }

      _navigate(next);
    });

    return Scaffold(
      backgroundColor: AppTheme.primaryTeal,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // ── Logo ────────────────────────────────────────────────────────
            Container(
              width:  96,
              height: 96,
              decoration: BoxDecoration(
                color:        Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Icon(
                Icons.school_rounded,
                size:  52,
                color: Colors.white,
              ),
            ),

            const SizedBox(height: 24),

            // ── App Name ─────────────────────────────────────────────────────
            const Text(
              'EduPay',
              style: TextStyle(
                color:         Colors.white,
                fontSize:      36,
                fontWeight:    FontWeight.w700,
                letterSpacing: -1,
              ),
            ),

            const SizedBox(height: 8),

            Text(
              'Tuition Fee Management',
              style: TextStyle(
                color:    Colors.white.withOpacity(0.8),
                fontSize: 16,
              ),
            ),

            const SizedBox(height: 64),

            // ── Loading Indicator ─────────────────────────────────────────────
            SizedBox(
              width:  32,
              height: 32,
              child: CircularProgressIndicator(
                color:       Colors.white.withOpacity(0.8),
                strokeWidth: 2.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _fallbackTimer?.cancel();
    super.dispose();
  }
}