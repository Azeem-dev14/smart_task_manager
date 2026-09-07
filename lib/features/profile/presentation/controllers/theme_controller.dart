import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smart_task_manager/core/constants/app_constants.dart';
import 'package:smart_task_manager/core/storage/hive_service.dart';
import 'package:smart_task_manager/features/auth/data/auth_repository.dart';
import 'package:smart_task_manager/features/profile/data/profile_repository.dart';

/// Serializes a [ThemeMode] to the value stored in Firestore and local storage.
String themeModeToStorage(ThemeMode mode) {
  switch (mode) {
    case ThemeMode.light:
      return 'light';
    case ThemeMode.dark:
      return 'dark';
    case ThemeMode.system:
      return 'system';
  }
}

/// Parses a stored theme preference, defaulting to [ThemeMode.system].
ThemeMode themeModeFromStorage(String? value) {
  switch (value) {
    case 'light':
      return ThemeMode.light;
    case 'dark':
      return ThemeMode.dark;
    default:
      return ThemeMode.system;
  }
}

/// Riverpod notifier owning the active [ThemeMode].
///
/// The signed-in user's Firestore preference is authoritative, so the theme is
/// re-applied automatically as soon as a profile loads. Before anyone signs in
/// (and while offline) the last locally persisted value is used, which keeps the
/// chosen appearance stable across restarts.
class ThemeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    final user = ref.watch(currentUserProvider);
    if (user != null) return themeModeFromStorage(user.themeMode);

    final saved = ref.watch(hiveServiceProvider).getSetting(AppConstants.keyThemeMode);
    return themeModeFromStorage(saved as String?);
  }

  /// Sets [mode] and persists it to local storage and Firestore.
  Future<void> setTheme(ThemeMode mode) async {
    if (state == mode) return;
    state = mode;

    final value = themeModeToStorage(mode);
    final user = ref.read(currentUserProvider);

    await ref.read(profileRepositoryProvider).updateThemeMode(
          userId: user?.uid ?? '',
          themeMode: value,
        );

    // Keep the cached profile in step so the preference survives a restart and
    // stays consistent with what the profile screen displays.
    if (user != null) {
      await ref.read(authRepositoryProvider).cacheUser(user.copyWith(themeMode: value));
    }
  }

  /// Toggles between light and dark mode.
  ///
  /// While following the system setting, the toggle resolves against the
  /// platform brightness so the first tap always visibly flips the theme.
  Future<void> toggleTheme() {
    final isDark = state == ThemeMode.dark ||
        (state == ThemeMode.system &&
            WidgetsBinding.instance.platformDispatcher.platformBrightness ==
                Brightness.dark);

    return setTheme(isDark ? ThemeMode.light : ThemeMode.dark);
  }
}

/// Provider managing the active application [ThemeMode].
final themeControllerProvider = NotifierProvider<ThemeNotifier, ThemeMode>(ThemeNotifier.new);
