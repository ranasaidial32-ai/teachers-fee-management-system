// lib/core/providers/providers.dart
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import '../network/api_client.dart';
import '../services/storage_service.dart';
import '../../features/auth/data/auth_state.dart';
import '../../features/auth/data/auth_repository.dart';
import '../../features/chat/services/socket_service.dart';

// ── Storage Service ───────────────────────────────────────────────────────────
// FIX: Use keepAlive so StorageService is never garbage-collected between
// reads. If it were disposed and recreated, Hive boxes would be re-opened
// and secure storage handles would be lost — causing blank reads that make
// the session restore return null and log the user out unexpectedly.
final storageServiceProvider = Provider<StorageService>((ref) {
  final service = StorageService();
  // Prevent disposal for the lifetime of the app
  ref.keepAlive();
  return service;
});

// ── Auth State ────────────────────────────────────────────────────────────────
// FIX: StateNotifierProvider is already kept alive by default (not
// auto-disposed), but we make the dependency chain explicit so that
// storageServiceProvider is always resolved before AuthStateNotifier
// starts its _restoreSession() call in the constructor.
final authStateProvider = StateNotifierProvider<AuthStateNotifier, AuthState>(
  (ref) {
    // Watch (not read) so if storageService ever rebuilds, auth rebuilds too
    final storage = ref.watch(storageServiceProvider);
    return AuthStateNotifier(storageService: storage);
  },
);

// ── API Client ────────────────────────────────────────────────────────────────
// FIX: onTokenExpired must call logout() on the notifier — not create a new
// one. ref.read is correct here (not watch) because we want the current
// notifier instance, not a reactive dependency.
final apiClientProvider = Provider<ApiClient>((ref) {
  final storage      = ref.watch(storageServiceProvider);
  final authNotifier = ref.read(authStateProvider.notifier); // read not watch

  return ApiClient(
    storageService: storage,
    onTokenExpired: authNotifier.logout,
  );
});

// ── Auth Repository ───────────────────────────────────────────────────────────
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(
    apiClient:      ref.watch(apiClientProvider),
    storageService: ref.watch(storageServiceProvider),
  );
});

// ── Socket Service ────────────────────────────────────────────────────────────
final socketServiceProvider = Provider<SocketService>((ref) {
  final storage = ref.watch(storageServiceProvider);
  final service = SocketService(storageService: storage);

  // FIX: Only connect/disconnect on actual transitions, not every rebuild.
  // The previous code would reconnect on every provider rebuild because
  // ref.listen fires on every state change including unrelated fields.
  ref.listen<AuthState>(authStateProvider, (previous, next) {
    final wasAuthenticated = previous?.isAuthenticated ?? false;
    final isAuthenticated  = next.isAuthenticated;

    if (isAuthenticated && !wasAuthenticated) {
      service.connect();
    } else if (!isAuthenticated && wasAuthenticated) {
      service.disconnect();
    }
  });

  ref.onDispose(service.dispose);
  return service;
});

// ── Connectivity ──────────────────────────────────────────────────────────────
// FIX: connectivity_plus 6.x onConnectivityChanged now emits
// List<ConnectivityResult> not a single ConnectivityResult.
// The old check `result != ConnectivityResult.none` would throw a
// type error at runtime on newer versions of the package.
final connectivityProvider = StreamProvider<bool>((ref) async* {
  // Emit true immediately — assume online until first real check
  yield true;

  await for (final result in Connectivity().onConnectivityChanged) {
    // Handle both old (single) and new (list) emission formats
    if (result is List<ConnectivityResult>) {
      yield result.any((r) => r != ConnectivityResult.none);
    } else if (result is ConnectivityResult) {
      yield result != ConnectivityResult.none;
    } else {
      // Unknown type — assume connected to avoid false offline banners
      yield true;
    }
  }
});