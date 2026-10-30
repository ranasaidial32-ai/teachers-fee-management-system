// lib/core/router/app_router.dart
library;

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../constants/app_constants.dart';
import '../providers/providers.dart';
import '../theme/app_theme.dart';
import '../../features/auth/data/auth_state.dart';
import '../../features/auth/presentation/pages/splash_page.dart';
import '../../features/auth/presentation/pages/login_page.dart';
import '../../features/auth/presentation/pages/register_page.dart';
import '../../features/teacher/presentation/pages/teacher_home_page.dart';
import '../../features/teacher/presentation/pages/batch_detail_page.dart';
import '../../features/teacher/presentation/pages/create_batch_page.dart';
import '../../features/teacher/presentation/pages/fee_management_page.dart';
import '../../features/student/presentation/pages/student_home_page.dart';
import '../../features/student/presentation/pages/student_fee_page.dart';
import '../../features/chat/presentation/pages/chat_page.dart';
import '../../features/files/presentation/pages/file_list_page.dart';
import '../../features/notifications/presentation/pages/notifications_page.dart';
import '../../features/auth/presentation/pages/profile_page.dart';

// ── Navigator Keys ────────────────────────────────────────────────────────────
final _rootNavigatorKey    = GlobalKey<NavigatorState>(debugLabel: 'root');
final _teacherNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'teacher');
final _studentNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'student');

// ── Router Provider ───────────────────────────────────────────────────────────
final appRouterProvider = Provider<GoRouter>((ref) {
  // FIX: Build the refreshListenable from the StateNotifier's stream.
  // StateNotifier exposes a .stream of state changes — we subscribe to it
  // and call notifyListeners() so GoRouter re-evaluates redirect on every
  // auth state transition (initial→unauthenticated, unauth→authenticated…).
  final authNotifier = ref.watch(authStateProvider.notifier);
  final refreshListenable = _AuthChangeNotifier(authNotifier.stream);

  // Dispose the listenable when the provider is disposed
  ref.onDispose(refreshListenable.dispose);

  return GoRouter(
    navigatorKey:        _rootNavigatorKey,
    initialLocation:     AppConstants.routeSplash,
    debugLogDiagnostics: true,
    refreshListenable:   refreshListenable,

    redirect: (BuildContext context, GoRouterState state) {
      final authState   = ref.read(authStateProvider);
      final status      = authState.status;
      final currentPath = state.matchedLocation;

      debugPrint('Router redirect: status=$status, path=$currentPath');

      // ── CRITICAL: Do not redirect while auth is still initialising ──────
      // Returning null lets the splash page sit and wait for _restoreSession
      // to complete. Without this guard, GoRouter would see isAuthenticated=false
      // during init and immediately bounce to /login before auth resolves.
      if (status == AuthStatus.initial || status == AuthStatus.loading) {
        return null;
      }

      final isOnSplash   = currentPath == AppConstants.routeSplash;
      final isOnLogin    = currentPath == AppConstants.routeLogin;
      final isOnRegister = currentPath == AppConstants.routeRegister;
      final isOnPublic   = isOnSplash || isOnLogin || isOnRegister;

      // ── Unauthenticated / Error ──────────────────────────────────────────
      if (status == AuthStatus.unauthenticated || status == AuthStatus.error) {
        if (isOnPublic) return null;
        return AppConstants.routeLogin;
      }

      // ── Authenticated ────────────────────────────────────────────────────
      if (status == AuthStatus.authenticated) {
        final role = authState.role;

        // Leave splash / auth pages → go home
        if (isOnPublic) {
          return role == AppConstants.roleTeacher
              ? AppConstants.routeTeacherHome
              : AppConstants.routeStudentHome;
        }

        // Cross-role access guard
        if (role == AppConstants.roleStudent &&
            currentPath.startsWith('/teacher')) {
          return AppConstants.routeStudentHome;
        }
        if (role == AppConstants.roleTeacher &&
            currentPath.startsWith('/student')) {
          return AppConstants.routeTeacherHome;
        }
      }

      return null;
    },

    routes: [
      // ── Public ───────────────────────────────────────────────────────────
      GoRoute(
        path:    AppConstants.routeSplash,
        name:    'splash',
        builder: (context, state) => const SplashPage(),
      ),
      GoRoute(
        path:    AppConstants.routeLogin,
        name:    'login',
        builder: (context, state) => const LoginPage(),
      ),
      GoRoute(
        path:    AppConstants.routeRegister,
        name:    'register',
        builder: (context, state) => const RegisterPage(),
      ),

      // ── Teacher Shell ─────────────────────────────────────────────────────
      ShellRoute(
        navigatorKey: _teacherNavigatorKey,
        builder: (context, state, child) => TeacherShell(child: child),
        routes: [
          GoRoute(
            path:    AppConstants.routeTeacherHome,
            name:    'teacher-home',
            builder: (context, state) => const TeacherHomePage(),
          ),
          GoRoute(
            path:    '/teacher/create-batch',
            name:    'create-batch',
            builder: (context, state) => const CreateBatchPage(),
          ),
          GoRoute(
            path:    '/teacher/batch/:id',
            name:    'batch-detail',
            builder: (context, state) {
              final batchId = state.pathParameters['id']!;
              return BatchDetailPage(batchId: batchId);
            },
          ),
          GoRoute(
            path:    '/teacher/fees/:batchId',
            name:    'fee-management',
            builder: (context, state) {
              final batchId = state.pathParameters['batchId']!;
              return FeeManagementPage(batchId: batchId);
            },
          ),
          GoRoute(
            path:    '/teacher/notifications',
            name:    'teacher-notifications',
            builder: (context, state) => const NotificationsPage(),
          ),
          GoRoute(
            path:    '/teacher/profile',
            name:    'teacher-profile',
            builder: (context, state) => const ProfilePage(),
          ),
        ],
      ),

      // ── Student Shell ─────────────────────────────────────────────────────
      ShellRoute(
        navigatorKey: _studentNavigatorKey,
        builder: (context, state, child) => StudentShell(child: child),
        routes: [
          GoRoute(
            path:    AppConstants.routeStudentHome,
            name:    'student-home',
            builder: (context, state) => const StudentHomePage(),
          ),
          GoRoute(
            path:    '/student/fees',
            name:    'student-fees',
            builder: (context, state) => const StudentFeePage(),
          ),
          GoRoute(
            path:    '/student/notifications',
            name:    'student-notifications',
            builder: (context, state) => const NotificationsPage(),
          ),
          GoRoute(
            path:    '/student/profile',
            name:    'student-profile',
            builder: (context, state) => const ProfilePage(),
          ),
        ],
      ),

      // ── Full-Screen Shared Routes (above shells) ──────────────────────────
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path:    '/chat/:batchId',
        name:    'chat',
        builder: (context, state) {
          final batchId   = state.pathParameters['batchId']!;
          final batchName = state.uri.queryParameters['name'] ?? 'Chat';
          return ChatPage(batchId: batchId, batchName: batchName);
        },
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path:    '/files/:batchId',
        name:    'file-list',
        builder: (context, state) {
          final batchId = state.pathParameters['batchId']!;
          return FileListPage(batchId: batchId);
        },
      ),
    ],

    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              'Page not found',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(state.error?.message ?? 'Unknown error'),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => context.go(AppConstants.routeLogin),
              child: const Text('Go to Login'),
            ),
          ],
        ),
      ),
    ),
  );
});

// ── Auth Change Notifier ──────────────────────────────────────────────────────
// FIX: AuthStateNotifier is a Riverpod StateNotifier, NOT a ChangeNotifier.
// It does NOT have addListener/removeListener.
// Instead, StateNotifier exposes a `.stream` (a Dart Stream<S>) that emits
// every time state changes. We subscribe to that stream and forward each
// emission to ChangeNotifier.notifyListeners() so GoRouter refreshes.
class _AuthChangeNotifier extends ChangeNotifier {
  _AuthChangeNotifier(Stream<AuthState> stream) {
    // Subscribe immediately — fires notifyListeners on every auth state change
    _subscription = stream.listen((_) {
      notifyListeners();
    });
  }

  late final StreamSubscription<AuthState> _subscription;

  @override
  void dispose() {
    // Cancel stream subscription to prevent memory leaks
    _subscription.cancel();
    super.dispose();
  }
}

// ── Shell Wrappers ────────────────────────────────────────────────────────────
class TeacherShell extends StatelessWidget {
  const TeacherShell({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: child,
        bottomNavigationBar: const _TeacherBottomNav(),
      );
}

class StudentShell extends StatelessWidget {
  const StudentShell({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: child,
        bottomNavigationBar: const _StudentBottomNav(),
      );
}

// ── Teacher Bottom Nav ────────────────────────────────────────────────────────
class _TeacherBottomNav extends StatelessWidget {
  const _TeacherBottomNav();

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    final isDark   = Theme.of(context).brightness == Brightness.dark;

    int currentIndex = 0;
    if (location.contains('/teacher/home'))          currentIndex = 0;
    if (location.contains('/teacher/fees'))          currentIndex = 1;
    if (location.contains('/teacher/notifications')) currentIndex = 2;
    if (location.contains('/teacher/profile'))       currentIndex = 3;

    return _NavBar(
      isDark:       isDark,
      currentIndex: currentIndex,
      items: const [
        _NavBarItem(
          icon:       Icons.dashboard_outlined,
          activeIcon: Icons.dashboard_rounded,
          label:      'Batches',
        ),
        _NavBarItem(
          icon:       Icons.account_balance_wallet_outlined,
          activeIcon: Icons.account_balance_wallet_rounded,
          label:      'Fees',
        ),
        _NavBarItem(
          icon:       Icons.notifications_outlined,
          activeIcon: Icons.notifications_rounded,
          label:      'Alerts',
        ),
        _NavBarItem(
          icon:       Icons.person_outline_rounded,
          activeIcon: Icons.person_rounded,
          label:      'Profile',
        ),
      ],
      onTap: (index) {
        switch (index) {
          case 0: context.go(AppConstants.routeTeacherHome);  break;
          case 1: context.go('/teacher/notifications');       break;
          case 2: context.go('/teacher/notifications');       break;
          case 3: context.go('/teacher/profile');             break;
        }
      },
    );
  }
}

// ── Student Bottom Nav ────────────────────────────────────────────────────────
class _StudentBottomNav extends StatelessWidget {
  const _StudentBottomNav();

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    final isDark   = Theme.of(context).brightness == Brightness.dark;

    int currentIndex = 0;
    if (location.contains('/student/home'))          currentIndex = 0;
    if (location.contains('/student/fees'))          currentIndex = 1;
    if (location.contains('/student/notifications')) currentIndex = 2;
    if (location.contains('/student/profile'))       currentIndex = 3;

    return _NavBar(
      isDark:       isDark,
      currentIndex: currentIndex,
      items: const [
        _NavBarItem(
          icon:       Icons.home_outlined,
          activeIcon: Icons.home_rounded,
          label:      'Home',
        ),
        _NavBarItem(
          icon:       Icons.receipt_long_outlined,
          activeIcon: Icons.receipt_long_rounded,
          label:      'My Fees',
        ),
        _NavBarItem(
          icon:       Icons.notifications_outlined,
          activeIcon: Icons.notifications_rounded,
          label:      'Alerts',
        ),
        _NavBarItem(
          icon:       Icons.person_outline_rounded,
          activeIcon: Icons.person_rounded,
          label:      'Profile',
        ),
      ],
      onTap: (index) {
        switch (index) {
          case 0: context.go(AppConstants.routeStudentHome); break;
          case 1: context.go('/student/fees');               break;
          case 2: context.go('/student/notifications');      break;
          case 3: context.go('/student/profile');            break;
        }
      },
    );
  }
}

// ── Shared Nav Bar ────────────────────────────────────────────────────────────
class _NavBarItem {
  const _NavBarItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
  });
  final IconData icon;
  final IconData activeIcon;
  final String   label;
}

class _NavBar extends StatelessWidget {
  const _NavBar({
    required this.isDark,
    required this.currentIndex,
    required this.items,
    required this.onTap,
  });

  final bool              isDark;
  final int               currentIndex;
  final List<_NavBarItem> items;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final bgColor         = isDark
        ? const Color(0xFF182030)
        : Colors.white;
    final selectedColor   = isDark
        ? AppTheme.primaryTealLight
        : AppTheme.primaryTeal;
    final unselectedColor = isDark
        ? const Color(0xFFB0BEC5)
        : const Color(0xFF546E7A);

    return Container(
      decoration: BoxDecoration(
        color: bgColor,
        border: Border(
          top: BorderSide(
            color: isDark
                ? const Color(0xFF263238)
                : const Color(0xFFECEFF1),
            width: 1,
          ),
        ),
        boxShadow: [
          BoxShadow(
            // FIX: withOpacity is deprecated — use withValues(alpha:)
            color:      Colors.black.withValues(alpha: isDark ? 0.3 : 0.06),
            blurRadius: 12,
            offset:     const Offset(0, -3),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(
            children: List.generate(items.length, (index) {
              final item       = items[index];
              final isSelected = index == currentIndex;
              final color      = isSelected ? selectedColor : unselectedColor;

              return Expanded(
                child: GestureDetector(
                  onTap:    () => onTap(index),
                  behavior: HitTestBehavior.opaque,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        curve:    Curves.easeInOut,
                        height:   34,
                        // FIX: withOpacity deprecated — use withValues(alpha:)
                        width:    isSelected ? 56 : 34,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? selectedColor.withValues(alpha: 0.15)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(17),
                        ),
                        child: Icon(
                          isSelected ? item.activeIcon : item.icon,
                          color: color,
                          size:  22,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        item.label,
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize:   10,
                          fontWeight: isSelected
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: color,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}