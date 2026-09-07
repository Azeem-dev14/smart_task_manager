import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:smart_task_manager/core/widgets/app_confirm_dialog.dart';
import 'package:smart_task_manager/core/widgets/error_view.dart';
import 'package:smart_task_manager/features/auth/data/auth_repository.dart';
import 'package:smart_task_manager/features/auth/presentation/screens/login_screen.dart';
import 'package:smart_task_manager/features/profile/data/profile_repository.dart';
import 'package:smart_task_manager/features/profile/presentation/controllers/theme_controller.dart';

/// Screen displaying user information, editable display name, theme toggle, and sign out.
class ProfileScreen extends ConsumerStatefulWidget {
  /// Constructs a [ProfileScreen].
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _nameController = TextEditingController();
  bool _isEditingName = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final user = ref.read(authRepositoryProvider).getCachedUser();
    _nameController.text = user?.name ?? '';
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  /// Saves updated user display name to Firestore and local storage.
  Future<void> _saveName() async {
    final newName = _nameController.text.trim();
    if (newName.isEmpty) return;

    setState(() => _isSaving = true);
    try {
      final user = ref.read(authRepositoryProvider).getCachedUser();
      if (user != null) {
        final profileRepo = ref.read(profileRepositoryProvider);
        final updated = await profileRepo.updateProfileName(
          userId: user.uid,
          name: newName,
        );
        await ref.read(authRepositoryProvider).cacheUser(updated);
        setState(() => _isEditingName = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Profile updated successfully!')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ErrorView.showSnackBar(context, e);
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  /// Displays confirmation dialog and signs user out.
  Future<void> _handleLogout() async {
    final confirmed = await AppConfirmDialog.show(
      context,
      title: 'Sign Out',
      message: 'Are you sure you want to sign out of your account?',
      confirmText: 'Sign Out',
      isDestructive: true,
    );

    if (confirmed) {
      await ref.read(authRepositoryProvider).logout();
      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = ref.watch(authRepositoryProvider).getCachedUser();
    final themeMode = ref.watch(themeControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile & Settings', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // User Avatar Header
            Center(
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 46,
                    backgroundColor: theme.colorScheme.primaryContainer,
                    child: Text(
                      (user?.name.isNotEmpty == true)
                          ? user!.name[0].toUpperCase()
                          : 'U',
                      style: TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    user?.name ?? 'User',
                    style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    user?.email ?? '',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                  if (user != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Member since ${DateFormat.yMMMd().format(user.createdAt)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 28),

            // Profile Information Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Personal Details',
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        IconButton(
                          icon: Icon(_isEditingName ? Icons.close : Icons.edit_outlined, size: 20),
                          onPressed: () {
                            setState(() {
                              _isEditingName = !_isEditingName;
                              if (!_isEditingName) {
                                _nameController.text = user?.name ?? '';
                              }
                            });
                          },
                        ),
                      ],
                    ),
                    const Divider(height: 16),
                    if (_isEditingName) ...[
                      TextFormField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          labelText: 'Display Name',
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton.tonal(
                          onPressed: _isSaving ? null : _saveName,
                          child: _isSaving
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Text('Save Changes'),
                        ),
                      ),
                    ] else ...[
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.person_outline),
                        title: const Text('Name'),
                        subtitle: Text(user?.name ?? 'Not set'),
                      ),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.email_outlined),
                        title: const Text('Email'),
                        subtitle: Text(user?.email ?? 'Not set'),
                      ),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.fingerprint_rounded),
                        title: const Text('User ID (API query param)'),
                        subtitle: Text(
                          user?.uid ?? '',
                          style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // App Appearance & Theme Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Appearance',
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Preferences are automatically synced to Firestore.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                    const Divider(height: 20),
                    Center(
                      child: SegmentedButton<ThemeMode>(
                        segments: const [
                          ButtonSegment(
                            value: ThemeMode.system,
                            icon: Icon(Icons.settings_suggest_outlined),
                            label: Text('System'),
                          ),
                          ButtonSegment(
                            value: ThemeMode.light,
                            icon: Icon(Icons.light_mode_outlined),
                            label: Text('Light'),
                          ),
                          ButtonSegment(
                            value: ThemeMode.dark,
                            icon: Icon(Icons.dark_mode_outlined),
                            label: Text('Dark'),
                          ),
                        ],
                        selected: {themeMode},
                        onSelectionChanged: (newSelection) {
                          ref.read(themeControllerProvider.notifier).setTheme(newSelection.first);
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Logout Button
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red.shade600,
                side: BorderSide(color: Colors.red.shade300),
                minimumSize: const Size.fromHeight(50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _handleLogout,
              icon: const Icon(Icons.logout_rounded),
              label: const Text('Sign Out', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
