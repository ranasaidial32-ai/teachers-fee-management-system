/// features/auth/presentation/pages/profile_page.dart
/// Added: avatar picker (5 preset images) + editable display name.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/avatar_constants.dart';
import '../../../../core/providers/providers.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../data/auth_repository.dart';

class ProfilePage extends ConsumerStatefulWidget {
  const ProfilePage({super.key});

  @override
  ConsumerState<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<ProfilePage> {
  // ── Edit-name state ────────────────────────────────────────────────────────
  bool               _isEditingName = false;
  late TextEditingController _nameController;
  bool               _isSavingName  = false;
  String?            _nameError;

  // ── Avatar state ───────────────────────────────────────────────────────────
  bool               _isSavingAvatar = false;

  @override
  void initState() {
    super.initState();
    final authState  = ref.read(authStateProvider);
    _nameController  = TextEditingController(text: authState.userName ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  // ── Save name ──────────────────────────────────────────────────────────────
  Future<void> _saveName() async {
    final newName = _nameController.text.trim();
    if (newName.isEmpty || newName.length < 2) {
      setState(() => _nameError = 'Name must be at least 2 characters.');
      return;
    }
    if (newName == ref.read(authStateProvider).userName) {
      setState(() { _isEditingName = false; _nameError = null; });
      return;
    }

    setState(() { _isSavingName = true; _nameError = null; });

    final repo   = ref.read(authRepositoryProvider);
    final result = await repo.updateProfile(name: newName);

    if (!mounted) return;

    if (result.isSuccess) {
      await ref.read(authStateProvider.notifier).updateProfile(
        newName: result.data!.name,
      );
      setState(() { _isEditingName = false; _isSavingName = false; });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:          Text('Name updated ✓'),
          backgroundColor:  AppTheme.primaryTeal,
          duration:         Duration(seconds: 2),
        ),
      );
    } else {
      setState(() {
        _nameError    = result.error;
        _isSavingName = false;
      });
    }
  }

  // ── Save avatar ─────────────────────────────────────────────────────────────
  Future<void> _saveAvatar(int avatarId) async {
    if (ref.read(authStateProvider).avatarId == avatarId) return;

    setState(() => _isSavingAvatar = true);

    final repo   = ref.read(authRepositoryProvider);
    final result = await repo.updateProfile(avatarId: avatarId);

    if (!mounted) return;

    if (result.isSuccess) {
      await ref.read(authStateProvider.notifier).updateProfile(
        newAvatarId: result.data!.avatarId,
      );
      setState(() => _isSavingAvatar = false);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:         Text('Avatar updated ✓'),
          backgroundColor: AppTheme.primaryTeal,
          duration:        Duration(seconds: 2),
        ),
      );
    } else {
      setState(() => _isSavingAvatar = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:         Text(result.error ?? 'Failed to update avatar.'),
          backgroundColor: AppTheme.errorRed,
        ),
      );
    }
  }

  // ── Show avatar picker ─────────────────────────────────────────────────────
  void _showAvatarPicker() {
    final currentAvatarId = ref.read(authStateProvider).avatarId;

    showModalBottomSheet(
      context:            context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _AvatarPickerSheet(
        currentAvatarId: currentAvatarId,
        isSaving:        _isSavingAvatar,
        onSelect:        (id) {
          Navigator.pop(context);
          _saveAvatar(id);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);
    final theme     = Theme.of(context);
    final isTeacher = authState.isTeacher;

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppConstants.screenPadding),
          child: Column(
            children: [
              const SizedBox(height: 16),

              // ── Avatar with edit button ─────────────────────────────────────
              Stack(
                children: [
                  // Main avatar — uses UserAvatar widget
                  UserAvatar(
                    name:     authState.userName ?? 'U',
                    avatarId: authState.avatarId,
                    radius:   52,
                    fontSize: 36,
                  ),

                  // Edit badge — bottom-right corner
                  Positioned(
                    right:  0,
                    bottom: 0,
                    child: GestureDetector(
                      onTap: _showAvatarPicker,
                      child: Container(
                        width:       32,
                        height:      32,
                        decoration: BoxDecoration(
                          color:       AppTheme.primaryTeal,
                          shape:       BoxShape.circle,
                          border: Border.all(
                            color: theme.colorScheme.surface,
                            width: 2,
                          ),
                        ),
                        child: _isSavingAvatar
                            ? const Padding(
                                padding: EdgeInsets.all(6),
                                child:   CircularProgressIndicator(
                                  strokeWidth:  2,
                                  color:        Colors.white,
                                ),
                              )
                            : const Icon(
                                Icons.edit_rounded,
                                size:  16,
                                color: Colors.white,
                              ),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // ── Editable Name ───────────────────────────────────────────────
              if (_isEditingName)
                _NameEditField(
                  controller: _nameController,
                  isSaving:   _isSavingName,
                  error:      _nameError,
                  onSave:     _saveName,
                  onCancel: () => setState(() {
                    _isEditingName = false;
                    _nameError     = null;
                    _nameController.text = authState.userName ?? '';
                  }),
                )
              else
                _NameDisplay(
                  name:    authState.userName ?? 'User',
                  onEdit:  () => setState(() => _isEditingName = true),
                  theme:   theme,
                ),

              const SizedBox(height: 4),

              // ── Email ───────────────────────────────────────────────────────
              Text(
                authState.userEmail ?? '',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),

              const SizedBox(height: 12),

              // ── Role Badge ──────────────────────────────────────────────────
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                  color: isTeacher
                      ? AppTheme.primaryTeal.withValues(alpha: 0.1)
                      : AppTheme.secondaryAmber.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isTeacher
                        ? AppTheme.primaryTeal.withValues(alpha: 0.3)
                        : AppTheme.secondaryAmber.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isTeacher
                          ? Icons.admin_panel_settings_rounded
                          : Icons.school_rounded,
                      size:  16,
                      color: isTeacher
                          ? AppTheme.primaryTeal
                          : AppTheme.secondaryAmberDark,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      isTeacher ? 'Teacher (Admin)' : 'Student',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: isTeacher
                            ? AppTheme.primaryTeal
                            : AppTheme.secondaryAmberDark,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 40),

              // ── Info Cards ──────────────────────────────────────────────────
              _InfoCard(
                icon:  Icons.email_outlined,
                label: 'Email',
                value: authState.userEmail ?? '—',
              ),

              const SizedBox(height: 8),

              _InfoCard(
                icon:  Icons.badge_outlined,
                label: 'User ID',
                value: authState.userId != null
                    ? '${authState.userId!.substring(0, 8)}...'
                    : '—',
              ),

              const SizedBox(height: 40),

              // ── Logout ──────────────────────────────────────────────────────
              SizedBox(
                width:  double.infinity,
                height: 52,
                child: OutlinedButton.icon(
                  onPressed: () => _confirmLogout(context, ref),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.errorRed,
                    side: const BorderSide(color: AppTheme.errorRed),
                  ),
                  icon:  const Icon(Icons.logout_rounded),
                  label: const Text('Sign Out'),
                ),
              ),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmLogout(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title:   const Text('Sign Out'),
        content: const Text('Are you sure you want to sign out of EduPay?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child:     const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.errorRed),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final authRepo = ref.read(authRepositoryProvider);
      await authRepo.logout();
      await ref.read(authStateProvider.notifier).logout();
    }
  }
}

// ── Name Display ──────────────────────────────────────────────────────────────

class _NameDisplay extends StatelessWidget {
  const _NameDisplay({
    required this.name,
    required this.onEdit,
    required this.theme,
  });
  final String     name;
  final VoidCallback onEdit;
  final ThemeData  theme;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize:      MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      Text(
        name,
        style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
      ),
      const SizedBox(width: 6),
      GestureDetector(
        onTap: onEdit,
        child: Icon(
          Icons.edit_outlined,
          size:  18,
          color: AppTheme.primaryTeal.withValues(alpha: 0.7),
        ),
      ),
    ],
  );
}

// ── Name Edit Field ───────────────────────────────────────────────────────────

class _NameEditField extends StatelessWidget {
  const _NameEditField({
    required this.controller,
    required this.isSaving,
    required this.onSave,
    required this.onCancel,
    this.error,
  });

  final TextEditingController controller;
  final bool                  isSaving;
  final VoidCallback           onSave;
  final VoidCallback           onCancel;
  final String?                error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                autofocus:  true,
                maxLength:  120,
                decoration: InputDecoration(
                  hintText:    'Enter your name',
                  errorText:   error,
                  filled:      true,
                  fillColor:   theme.colorScheme.surfaceContainerHighest,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:   BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                      color: AppTheme.primaryTeal,
                      width: 1.5,
                    ),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical:   12,
                  ),
                  counterText: '',
                ),
                onSubmitted: (_) => onSave(),
              ),
            ),
            const SizedBox(width: 8),

            // Save button
            isSaving
                ? const SizedBox(
                    width:  36,
                    height: 36,
                    child:  CircularProgressIndicator(strokeWidth: 2),
                  )
                : IconButton(
                    onPressed: onSave,
                    icon: const Icon(Icons.check_circle_rounded),
                    color: AppTheme.primaryTeal,
                    iconSize: 32,
                    tooltip: 'Save name',
                  ),

            // Cancel button
            IconButton(
              onPressed: onCancel,
              icon:  const Icon(Icons.cancel_rounded),
              color: Colors.grey,
              iconSize: 28,
              tooltip: 'Cancel',
            ),
          ],
        ),
      ],
    );
  }
}

// ── Avatar Picker Sheet ───────────────────────────────────────────────────────

class _AvatarPickerSheet extends StatefulWidget {
  const _AvatarPickerSheet({
    required this.currentAvatarId,
    required this.isSaving,
    required this.onSelect,
  });

  final int?          currentAvatarId;
  final bool          isSaving;
  final void Function(int id) onSelect;

  @override
  State<_AvatarPickerSheet> createState() => _AvatarPickerSheetState();
}

class _AvatarPickerSheetState extends State<_AvatarPickerSheet> {
  int? _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.currentAvatarId;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Center(
            child: Container(
              width:  40,
              height: 4,
              decoration: BoxDecoration(
                color:        Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Title
          Text(
            'Choose your avatar',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Select one of the 5 preset profile pictures',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 28),

          // ── Avatar Grid (5 items in one row) ────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: AvatarConstants.all.map((option) {
              final isSelected = _selected == option.id;

              return GestureDetector(
                onTap: () => setState(() => _selected = option.id),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve:    Curves.easeInOut,
                  padding:  const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected
                          ? AppTheme.primaryTeal
                          : Colors.transparent,
                      width: 3,
                    ),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color:      AppTheme.primaryTeal.withValues(alpha: 0.3),
                              blurRadius: 8,
                              spreadRadius: 2,
                            ),
                          ]
                        : null,
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Avatar image
                      ClipOval(
                        child: Image.asset(
                          AvatarConstants.assetPath(option.id),
                          width:  60,
                          height: 60,
                          fit:    BoxFit.cover,
                          // Fallback circle if image asset missing
                          errorBuilder: (_, __, ___) => Container(
                            width:  60,
                            height: 60,
                            decoration: BoxDecoration(
                              color:  option.color.withValues(alpha: 0.2),
                              shape:  BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.person_rounded,
                              color: option.color,
                              size:  32,
                            ),
                          ),
                        ),
                      ),

                      // Selected checkmark overlay
                      if (isSelected)
                        Container(
                          width:  60,
                          height: 60,
                          decoration: BoxDecoration(
                            color: AppTheme.primaryTeal.withValues(alpha: 0.35),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.check_rounded,
                            color: Colors.white,
                            size:  28,
                          ),
                        ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 32),

          // ── Confirm button ──────────────────────────────────────────────────
          SizedBox(
            width:  double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _selected == null || widget.isSaving
                  ? null
                  : () => widget.onSelect(_selected!),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryTeal,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: widget.isSaving
                  ? const SizedBox(
                      width:  22,
                      height: 22,
                      child:  CircularProgressIndicator(
                        strokeWidth: 2,
                        color:       Colors.white,
                      ),
                    )
                  : const Text(
                      'Confirm Avatar',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize:   15,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Info Card ─────────────────────────────────────────────────────────────────

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.icon,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final String   label;
  final String   value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color:        theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppTheme.primaryTeal),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}