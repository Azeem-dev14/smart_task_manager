import 'dart:developer' as dev;

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smart_task_manager/app.dart';
import 'package:smart_task_manager/core/database/app_database.dart';
import 'package:smart_task_manager/core/network/api_client.dart';
import 'package:smart_task_manager/core/storage/hive_service.dart';
import 'package:smart_task_manager/features/auth/data/auth_repository.dart';
import 'package:smart_task_manager/firebase_options.dart';

/// Main application entry point.
///
/// Initializes Flutter bindings, starts Firebase (falling back to a local-only
/// mode if it is unavailable), opens local storage, and launches the root widget
/// inside a [ProviderScope] with the runtime dependencies injected.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Firebase — a failure here must not brick the app; auth and profile both
  //    degrade to a local-only mode when Firebase is not configured.
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    dev.log('Firebase initialized successfully', name: 'AppInit');
  } catch (e) {
    dev.log(
      'Firebase initialization skipped/failed: $e (using local fallback mode)',
      name: 'AppInit',
    );
  }

  // 2. Hive — session cache and theme preference.
  final hiveService = HiveService();
  await hiveService.init();

  // 3. Drift SQLite — single source of truth for the offline-first task cache.
  final appDatabase = AppDatabase();

  runApp(
    ProviderScope(
      overrides: [
        hiveServiceProvider.overrideWithValue(hiveService),
        appDatabaseProvider.overrideWithValue(appDatabase),
        // The API client injects `user_id` on every request; it reads the UID
        // lazily so it always reflects the currently signed-in account.
        apiClientProvider.overrideWith(
          (ref) => ApiClient(
            getUserId: () => ref.read(authRepositoryProvider).currentUser?.uid,
          ),
        ),
      ],
      child: const SmartTaskManagerApp(),
    ),
  );
}
