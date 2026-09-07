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
/// Initializes Flutter bindings, handles Firebase startup with a graceful fallback,
/// initializes local Hive key-value storage, sets up the Drift SQLite database,
/// and launches the root widget inside a [ProviderScope].
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Initialize Firebase (graceful catch if credentials not yet configured)
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    dev.log('Firebase initialized successfully', name: 'AppInit');
  } catch (e) {
    dev.log(
      'Firebase initialization skipped/failed: $e (using local fallback mode)',
      name: 'AppInit',
    );
  }

  // 2. Initialize Hive local key-value storage (for user profile & app settings)
  final hiveService = HiveService();
  await hiveService.init();

  // 3. Initialize Drift SQLite database (single source of truth for offline-first tasks)
  final appDb = AppDatabase();

  // 4. Run application wrapped in Riverpod ProviderScope with dependency overrides
  runApp(
    ProviderScope(
      overrides: [
        hiveServiceProvider.overrideWithValue(hiveService),
        appDatabaseProvider.overrideWithValue(appDb),
        apiClientProvider.overrideWith((ref) {
          return ApiClient(
            getUserId: () =>
                ref.read(authRepositoryProvider).getCachedUser()?.uid,
          );
        }),
      ],
      child: const SmartTaskManagerApp(),
    ),
  );
}
