import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:smart_task_manager/core/constants/app_constants.dart';
import 'package:smart_task_manager/core/errors/app_exceptions.dart';
import 'package:smart_task_manager/core/storage/hive_service.dart';
import 'package:smart_task_manager/features/auth/domain/user_model.dart';
import 'package:smart_task_manager/features/profile/data/profile_repository.dart';

/// [ProfileRepository]'s local fallback path — exercised the same way as
/// [AuthRepository]'s, since `Firebase.apps` is empty in a plain
/// `flutter test` process (`isFirebaseAvailable` is false throughout).
void main() {
  late Directory tempDir;
  late HiveService hiveService;
  late ProfileRepository repo;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('profile_repo_test');
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
    repo = ProfileRepository(hiveService: hiveService);
  });

  UserModel user({String themeMode = 'system'}) => UserModel(
        uid: 'u1',
        name: 'Jamie Rivera',
        email: 'jamie@example.com',
        createdAt: DateTime(2026, 1, 1),
        themeMode: themeMode,
      );

  group('saveUserProfile / fetchUserProfile round trip (local cache)', () {
    test('a profile cached by AuthRepository.cacheUser is returned by a fetch', () async {
      // ProfileRepository doesn't own the cached session — AuthRepository
      // does (see its class doc) — so this seeds the same key it writes,
      // simulating a user already signed in when Firestore isn't reachable.
      await hiveService.putSetting(AppConstants.keyCachedUser, user().toJson());

      final fetched = await repo.fetchUserProfile('u1');

      expect(fetched.name, 'Jamie Rivera');
      expect(fetched.email, 'jamie@example.com');
      expect(fetched.themeMode, 'system');
    });

    test('fetching with no cache and no fallback throws CacheException', () async {
      expect(
        () => repo.fetchUserProfile('missing-uid'),
        throwsA(isA<CacheException>()),
      );
    });

    test('fetching with no cache but a fallback returns the fallback', () async {
      final fallback = user();

      final fetched = await repo.fetchUserProfile('u1', fallback: fallback);

      expect(fetched.uid, fallback.uid);
      expect(fetched.name, fallback.name);
    });
  });

  group('Theme preference persistence', () {
    test('saveUserProfile persists themeMode so it survives a restart', () async {
      await repo.saveUserProfile(user(themeMode: 'dark'));

      expect(hiveService.getSetting(AppConstants.keyThemeMode), 'dark');
    });

    test('updateThemeMode writes locally even without a Firestore connection', () async {
      await repo.updateThemeMode(userId: 'u1', themeMode: 'light');

      expect(hiveService.getSetting(AppConstants.keyThemeMode), 'light');
    });

    test('updateThemeMode with an empty userId still persists locally', () async {
      // Guards the pre-login case, where there's no signed-in user yet but a
      // theme choice should still stick.
      await repo.updateThemeMode(userId: '', themeMode: 'dark');

      expect(hiveService.getSetting(AppConstants.keyThemeMode), 'dark');
    });
  });
}
