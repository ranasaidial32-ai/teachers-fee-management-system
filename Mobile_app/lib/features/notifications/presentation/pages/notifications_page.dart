/// features/notifications/presentation/pages/notifications_page.dart
/// Notification history page for both teachers and students.
///
/// PRD Reference: Section 05 — Notification System
///   fee_overdue, fee_paid, file_shared, chat_message types
///
/// PRD Reference: Section 01 — Success Metrics
///   "≥90% notification delivery rate"
///
/// FEATURES:
///   List of received notifications with type icons
///   Type filter chips (All, Fee, Files)
///   Navigate to relevant page on tap
///   Unread count badge

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../../../core/constants/app_constants.dart';
import '../../../../core/providers/providers.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/notification_repository.dart';

// ── Provider ──────────────────────────────────────────────────────────────────

final _notifFilterProvider = StateProvider<String>((_) => 'all');

final _notificationsProvider =
    FutureProvider.autoDispose.family<List<NotificationModel>, String>(
  (ref, type) async {
    final repo   = NotificationRepository(
      apiClient: ref.watch(apiClientProvider),
    );
    final result = await repo.getMyNotifications(
      type: type == 'all' ? null : type,
    );
    if (result.isSuccess) return result.data!;
    throw Exception(result.error);
  },
);

// ── Page ──────────────────────────────────────────────────────────────────────

class NotificationsPage extends ConsumerWidget {
  const NotificationsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter       = ref.watch(_notifFilterProvider);
    final notifsAsync  = ref.watch(_notificationsProvider(filter));
    final authState    = ref.watch(authStateProvider);
    final isStudent    = authState.isStudent;
    final theme        = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          // Only students access this via student route
          if (!isStudent)
            IconButton(
              icon:      const Icon(Icons.bar_chart_rounded),
              tooltip:   'Delivery Stats',
              onPressed: () {
                // Navigate to notification stats (teacher feature)
              },
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: _FilterChips(
            selected:   filter,
            onSelected: (f) =>
                ref.read(_notifFilterProvider.notifier).state = f,
          ),
        ),
      ),
      body: RefreshIndicator(
        color:     AppTheme.primaryTeal,
        onRefresh: () => ref.refresh(_notificationsProvider(filter).future),
        child: notifsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error:   (err, _) => Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 48, color: Colors.grey),
                const SizedBox(height: 12),
                Text(err.toString().replaceAll('Exception: ', '')),
                const SizedBox(height: 16),
                OutlinedButton(
                  onPressed: () =>
                      ref.invalidate(_notificationsProvider(filter)),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
          data: (notifs) {
            if (notifs.isEmpty) {
              return _EmptyNotifState();
            }
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: notifs.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final n = notifs[index];
                return _NotifCard(
                  notification: n,
                  onTap:        () => _handleTap(context, n, authState.role ?? ''),
                ).animate(delay: (index * 40).ms).fadeIn();
              },
            );
          },
        ),
      ),
    );
  }

  void _handleTap(
    BuildContext context,
    NotificationModel n,
    String role,
  ) {
    final prefix = role == AppConstants.roleTeacher ? '/teacher' : '/student';
    switch (n.type) {
      case 'fee_overdue':
      case 'fee_paid':
        if (role == AppConstants.roleStudent) {
          context.go('/student/fees');
        } else if (n.batchId != null) {
          context.go('/teacher/fees/${n.batchId}');
        }
        break;
      case 'file_shared':
        if (n.batchId != null) {
          context.go('/files/${n.batchId}');
        }
        break;
      default:
        break;
    }
  }
}

// ── Filter Chips ──────────────────────────────────────────────────────────────

class _FilterChips extends StatelessWidget {
  const _FilterChips({required this.selected, required this.onSelected});
  final String                  selected;
  final void Function(String)   onSelected;

  @override
  Widget build(BuildContext context) {
    final filters = [
      ('all',         'All'),
      ('fee_overdue', 'Overdue'),
      ('fee_paid',    'Paid'),
      ('file_shared', 'Files'),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: filters.map((f) {
          final isSelected = selected == f.$1;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label:    Text(f.$2),
              selected: isSelected,
              onSelected: (_) => onSelected(f.$1),
              selectedColor: AppTheme.primaryTeal,
              labelStyle: TextStyle(
                fontFamily: 'Inter',
                fontSize:   12,
                fontWeight: FontWeight.w600,
                color:      isSelected ? Colors.white : null,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ── Notification Card ─────────────────────────────────────────────────────────

class _NotifCard extends StatelessWidget {
  const _NotifCard({required this.notification, required this.onTap});
  final NotificationModel notification;
  final VoidCallback      onTap;

  @override
  Widget build(BuildContext context) {
    final theme     = Theme.of(context);
    final n         = notification;
    final icon      = _iconFor(n.type);
    final iconColor = _colorFor(n.type);
    DateTime? sentDate;
    try { sentDate = n.sentAt != null ? DateTime.parse(n.sentAt!).toLocal() : null; } catch (_) {}

    return InkWell(
      onTap:       onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color:        theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: n.type == 'fee_overdue'
                ? AppTheme.statusOverdue.withOpacity(0.3)
                : theme.colorScheme.outlineVariant,
          ),
        ),
        child: Row(
          children: [
            // Icon
            Container(
              width:  44,
              height: 44,
              decoration: BoxDecoration(
                color:        iconColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconColor, size: 22),
            ),

            const SizedBox(width: 14),

            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _titleFor(n),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _bodyFor(n),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withOpacity(0.5),
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),

            // Time
            if (sentDate != null)
              Text(
                timeago.format(sentDate, locale: 'en_short'),
                style: theme.textTheme.labelSmall?.copyWith(
                  color:    theme.colorScheme.onSurface.withOpacity(0.4),
                  fontSize: 10,
                ),
              ),
          ],
        ),
      ),
    );
  }

  IconData _iconFor(String type) {
    switch (type) {
      case 'fee_overdue':   return Icons.warning_rounded;
      case 'fee_paid':      return Icons.check_circle_rounded;
      case 'file_shared':   return Icons.attach_file_rounded;
      case 'chat_message':  return Icons.chat_bubble_rounded;
      default:              return Icons.notifications_rounded;
    }
  }

  Color _colorFor(String type) {
    switch (type) {
      case 'fee_overdue':   return AppTheme.statusOverdue;
      case 'fee_paid':      return AppTheme.statusPaid;
      case 'file_shared':   return AppTheme.primaryTeal;
      case 'chat_message':  return AppTheme.secondaryAmber;
      default:              return Colors.grey;
    }
  }

  String _titleFor(NotificationModel n) {
    switch (n.type) {
      case 'fee_overdue':   return 'Fee Overdue';
      case 'fee_paid':      return 'Payment Confirmed';
      case 'file_shared':   return 'New File Shared';
      case 'chat_message':  return 'New Message';
      default:              return 'Notification';
    }
  }

  String _bodyFor(NotificationModel n) {
    final payload = n.fcmPayload;
    switch (n.type) {
      case 'fee_overdue':
        return '${payload['batch_name'] ?? ''} — '
               '₹${payload['amount_due'] ?? ''} due for ${payload['month'] ?? ''}';
      case 'fee_paid':
        return '${payload['batch_name'] ?? ''} — '
               '₹${payload['amount_paid'] ?? ''} confirmed for ${payload['month'] ?? ''}';
      case 'file_shared':
        return '${payload['uploader_name'] ?? 'Teacher'} shared '
               '${payload['file_name'] ?? 'a file'} in ${payload['batch_name'] ?? ''}';
      default:
        return '';
    }
  }
}

class _EmptyNotifState extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.notifications_none_rounded,
          size:  64,
          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.15),
        ),
        const SizedBox(height: 16),
        Text(
          'No notifications yet',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
          ),
        ),
      ],
    ),
  );
}