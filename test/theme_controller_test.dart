import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:smart_task_manager/core/storage/hive_service.dart';
import 'package:smart_task_manager/features/auth/data/auth_repository.dart';
import 'package:smart_task_manager/features/auth/domain/user_model.dart';
import 'package:smart_task_manager/features/profile/presentation/controllers/theme_controller.dart';

/// Exercises the real Riverpod provider graph — [ThemeNotifier] through
/// [currentUserProvider] through [AuthRepository] — rather than poking at
/// any single class in isolation, so "the app should auto-apply the saved
/// theme" is verified the same way the running app actually wires it.
void main() {
  late Directory tempDir;
  late HiveService hiveService;
  late ProviderContainer container;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('theme_controller_test');
    Hive.init(tempDir.path);
  });

  tearDownAll(() async {
    await Hive.close();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  setUp(() async {
    hiveService = HiveService();
    await hiveService.init(useFlutterInit: false);
    await hiveService.settingsBox.clear();

    container = ProviderContainer(
      overrides: [hiveServiceProvider.overrideWithValue(hiveService)],
    );
  });

  tearDown(() => container.dispose());

  UserModel testUser({required String themeMode}) => UserModel(
        uid: 'test-uid',
        name: 'Test User',
        email: 'test@example.com',
        createdAt: DateTime(2026, 1, 1),
        themeMode: themeMode,
      );

  test('defaults to system with no signed-in user and no saved preference', () {
    expect(container.read(themeControllerProvider), ThemeMode.system);
  });

  test("a signed-in user's themeMode is applied automatically", () async {
    final authRepo = container.read(authRepositoryProvider);
    await authRepo.cacheUser(testUser(themeMode: 'dark'));
    await pumpEventQueue();

    expect(container.read(themeControllerProvider), ThemeMode.dark);
  });

  test('signing out falls back to the last locally persisted preference', () async {
    final authRepo = container.read(authRepositoryProvider);
    await authRepo.cacheUser(testUser(themeMode: 'light'));
    await pumpEventQueue();
    expect(container.read(themeControllerProvider), ThemeMode.light);

    await authRepo.logout();
    await pumpEventQueue();

    // Nothing wrote keyThemeMode directly in this test, so signing out
    // should fall back to system rather than crash or keep showing "light".
    expect(container.read(themeControllerProvider), ThemeMode.system);
  });

  test('setTheme persists the choice and keeps the cached user in step', () async {
    final authRepo = container.read(authRepositoryProvider);
    await authRepo.cacheUser(testUser(themeMode: 'system'));
    await pumpEventQueue();

    await container.read(themeControllerProvider.notifier).setTheme(ThemeMode.dark);

    expect(container.read(themeControllerProvider), ThemeMode.dark);
    expect(authRepo.currentUser?.themeMode, 'dark');
  });

  test('toggleTheme flips between light and dark', () async {
    final notifier = container.read(themeControllerProvider.notifier);

    await notifier.setTheme(ThemeMode.light);
    expect(container.read(themeControllerProvider), ThemeMode.light);

    await notifier.toggleTheme();
    expect(container.read(themeControllerProvider), ThemeMode.dark);

    await notifier.toggleTheme();
    expect(container.read(themeControllerProvider), ThemeMode.light);
  });
}
