import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smart_task_manager/core/constants/app_constants.dart';
import 'package:smart_task_manager/core/storage/hive_service.dart';
import 'package:smart_task_manager/features/auth/data/auth_repository.dart';
import 'package:smart_task_manager/features/profile/data/profile_repository.dart';

/// Riverpod state notifier managing active [ThemeMode] and syncing selections to Firestore and Hive.
class ThemeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    final hive = ref.watch(hiveServiceProvider);
    final saved = hive.getSetting(AppConstants.keyThemeMode) as String?;

    if (saved == 'light') return ThemeMode.light;
    if (saved == 'dark') return ThemeMode.dark;
    return ThemeMode.system;
  }

  /// Sets [mode] and persists change across local storage and remote Firestore.
  Future<void> setTheme(ThemeMode mode) async {
    state = mode;
    final modeStr = mode == ThemeMode.light
        ? 'light'
        : mode == ThemeMode.dark
            ? 'dark'
            : 'system';

    final user = ref.read(authRepositoryProvider).getCachedUser();
    final profileRepo = ref.read(profileRepositoryProvider);

    await profileRepo.updateThemeMode(
      userId: user?.uid ?? '',
      themeMode: modeStr,
    );
  }

  /// Toggles between light and dark mode.
  void toggleTheme() {
    if (state == ThemeMode.dark) {
      setTheme(ThemeMode.light);
    } else {
      setTheme(ThemeMode.dark);
    }
  }
}

/// Provider managing active application [ThemeMode].
final themeControllerProvider = NotifierProvider<ThemeNotifier, ThemeMode>(() {
  return ThemeNotifier();
});
