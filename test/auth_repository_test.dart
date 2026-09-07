import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:smart_task_manager/core/storage/hive_service.dart';
import 'package:smart_task_manager/features/auth/data/auth_repository.dart';

/// These tests exercise [AuthRepository]'s local fallback mode.
///
/// A plain `flutter test` process never calls `Firebase.initializeApp()`, so
/// `Firebase.apps` stays empty and `isFirebaseAvailable` is false throughout
/// — exactly the "no Firebase configured yet" mode the repository is
/// designed to degrade into, and it happens to be fully testable without any
/// Firebase mocking at all.
void main() {
  late Directory tempDir;
  late HiveService hiveService;
  late AuthRepository repo;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('auth_repo_test');
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
    repo = AuthRepository(hiveService: hiveService);
  });

  tearDown(() {
    repo.dispose();
  });

  group('Local fallback registration and login', () {
    test('register caches a user derived from the given name and email', () async {
      final user = await repo.register(
        name: 'Ada Lovelace',
        email: 'Ada@Example.com',
        password: 'secret123',
      );

      expect(user.name, 'Ada Lovelace');
      expect(user.email, 'Ada@Example.com');
      expect(user.uid, isNotEmpty);
      expect(repo.currentUser?.uid, user.uid);
    });

    test('login after local registration returns the same cached identity', () async {
      final registered = await repo.register(
        name: 'Grace Hopper',
        email: 'grace@example.com',
        password: 'secret123',
      );

      final loggedIn = await repo.login(email: 'grace@example.com', password: 'secret123');

      expect(loggedIn.uid, registered.uid);
      expect(loggedIn.name, 'Grace Hopper');
    });

    test('login with an unseen email creates a fresh local identity', () async {
      final user = await repo.login(email: 'new.user@example.com', password: 'whatever');

      expect(user.email, 'new.user@example.com');
      // No account existed yet, so the name falls back to the email's local part.
      expect(user.name, 'new.user');
    });

    test('the same email always maps to the same local uid', () async {
      final first = await repo.login(email: 'stable@example.com', password: 'x');
      await repo.logout();
      final second = await repo.login(email: 'stable@example.com', password: 'y');

      expect(second.uid, first.uid);
    });
  });

  group('Session persistence', () {
    test('cacheUser survives across repository instances (persisted to disk)', () async {
      final user = await repo.register(
        name: 'Persisted User',
        email: 'persisted@example.com',
        password: 'secret123',
      );

      final reloaded = AuthRepository(hiveService: hiveService);
      expect(reloaded.currentUser?.uid, user.uid);
      expect(reloaded.currentUser?.name, 'Persisted User');
      reloaded.dispose();
    });

    test('logout clears the cached session', () async {
      await repo.register(name: 'Someone', email: 'someone@example.com', password: 'secret123');
      expect(repo.currentUser, isNotNull);

      await repo.logout();

      expect(repo.currentUser, isNull);
      final reloaded = AuthRepository(hiveService: hiveService);
      expect(reloaded.currentUser, isNull);
      reloaded.dispose();
    });
  });

  group('authStateChanges stream', () {
    test('replays the current user to a subscriber that attaches late', () async {
      await repo.register(name: 'Late Subscriber', email: 'late@example.com', password: 'x');

      // Subscribing after the user already signed in must not miss it — this
      // is what lets a widget built after the fact still see the session.
      final first = await repo.authStateChanges.first;
      expect(first?.name, 'Late Subscriber');
    });

    test('emits null after logout and the new user after a subsequent login', () async {
      final events = <String?>[];
      final subscription = repo.authStateChanges.listen((u) => events.add(u?.uid));

      final first = await repo.register(name: 'A', email: 'a@example.com', password: 'x');
      await repo.logout();
      final second = await repo.login(email: 'b@example.com', password: 'x');

      await Future<void>.delayed(Duration.zero);
      await subscription.cancel();

      // [initial replay (signed out), A signs in, sign out, B signs in]
      expect(events, [null, first.uid, null, second.uid]);
    });
  });
}
