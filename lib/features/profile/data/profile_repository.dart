import 'dart:developer' as dev;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smart_task_manager/core/constants/app_constants.dart';
import 'package:smart_task_manager/core/errors/app_exceptions.dart';
import 'package:smart_task_manager/core/storage/hive_service.dart';
import 'package:smart_task_manager/features/auth/domain/user_model.dart';

/// Repository managing the user profile document stored in Cloud Firestore at
/// `users/{userId}` with `name`, `email`, `createdAt` and `themeMode` fields.
///
/// Session caching is intentionally delegated to the auth repository so a single
/// component owns the cached [UserModel]; this repository only persists the
/// theme preference locally, which the app needs before a profile is loaded.
class ProfileRepository {
  /// Local key-value storage service.
  final HiveService hiveService;

  /// Constructs a [ProfileRepository].
  ProfileRepository({required this.hiveService});

  /// Whether Firebase is available in the current environment.
  bool get isFirebaseAvailable => Firebase.apps.isNotEmpty;

  CollectionReference<Map<String, dynamic>> get _users =>
      FirebaseFirestore.instance.collection('users');

  /// Fetches the profile stored at `users/{userId}`.
  ///
  /// When the document does not exist yet (an account created outside this app,
  /// or a registration that failed midway) it is created from [fallback].
  /// If Firestore cannot be reached, the locally cached profile is returned so
  /// the app stays usable offline.
  Future<UserModel> fetchUserProfile(String userId, {UserModel? fallback}) async {
    if (isFirebaseAvailable) {
      try {
        final doc = await _users.doc(userId).get().timeout(AppConstants.firebaseTimeout);
        final data = doc.data();

        if (doc.exists && data != null) {
          final user = _fromFirestore(userId, data);
          await hiveService.putSetting(AppConstants.keyThemeMode, user.themeMode);
          return user;
        }

        if (fallback != null) {
          await saveUserProfile(fallback);
          return fallback;
        }
      } catch (e) {
        dev.log('Firestore profile fetch failed, using local cache: $e', name: 'ProfileRepo');
      }
    }

    final cached = _cachedProfile();
    if (cached != null) return cached;
    if (fallback != null) return fallback;

    throw const CacheException(
      'No profile found locally or remotely.',
      code: 'profile-not-found',
    );
  }

  /// Creates or merges the user profile document and persists the theme locally.
  Future<void> saveUserProfile(UserModel user) async {
    await hiveService.putSetting(AppConstants.keyThemeMode, user.themeMode);

    if (!isFirebaseAvailable) return;

    try {
      await _users.doc(user.uid).set({
        'name': user.name,
        'email': user.email,
        'createdAt': Timestamp.fromDate(user.createdAt),
        'themeMode': user.themeMode,
      }, SetOptions(merge: true)).timeout(AppConstants.firebaseTimeout);
    } catch (e) {
      // The profile stays cached locally and is re-synced on the next write.
      dev.log('Firestore profile save failed: $e', name: 'ProfileRepo');
    }
  }

  /// Persists the preferred theme mode ('system', 'light', 'dark').
  ///
  /// Writes locally first so the choice survives a restart even when the device
  /// is offline, then mirrors it to Firestore.
  Future<void> updateThemeMode({
    required String userId,
    required String themeMode,
  }) async {
    await hiveService.putSetting(AppConstants.keyThemeMode, themeMode);

    if (!isFirebaseAvailable || userId.isEmpty) return;

    try {
      await _users
          .doc(userId)
          .set({'themeMode': themeMode}, SetOptions(merge: true))
          .timeout(AppConstants.firebaseTimeout);
    } catch (e) {
      dev.log('Firestore theme sync failed: $e', name: 'ProfileRepo');
    }
  }

  UserModel? _cachedProfile() {
    final raw = hiveService.getSetting(AppConstants.keyCachedUser);
    if (raw is Map) {
      return UserModel.fromJson(Map<String, dynamic>.from(raw));
    }
    return null;
  }

  UserModel _fromFirestore(String userId, Map<String, dynamic> data) {
    final createdAt = data['createdAt'];

    return UserModel(
      uid: userId,
      name: data['name']?.toString() ?? '',
      email: data['email']?.toString() ?? '',
      createdAt: createdAt is Timestamp
          ? createdAt.toDate()
          : DateTime.tryParse(createdAt?.toString() ?? '') ?? DateTime.now(),
      themeMode: data['themeMode']?.toString() ?? 'system',
    );
  }
}

/// Riverpod provider for [ProfileRepository].
final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  final hive = ref.watch(hiveServiceProvider);
  return ProfileRepository(hiveService: hive);
});
