import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smart_task_manager/core/constants/app_constants.dart';
import 'package:smart_task_manager/core/errors/app_exceptions.dart';
import 'package:smart_task_manager/core/storage/hive_service.dart';
import 'package:smart_task_manager/features/auth/domain/user_model.dart';

/// Repository managing user profile persistence in Cloud Firestore (`users/{userId}`)
/// with bidirectional local caching via [HiveService].
class ProfileRepository {
  /// Local key-value storage service.
  final HiveService hiveService;

  /// Constructs a [ProfileRepository].
  ProfileRepository({required this.hiveService});

  /// Whether Firebase is available in the current environment.
  bool get isFirebaseAvailable => Firebase.apps.isNotEmpty;

  /// Fetches user profile from Firestore collection `users/{userId}`.
  ///
  /// Falls back to local Hive cache if Firestore request fails or is unavailable.
  Future<UserModel> fetchUserProfile(String userId) async {
    if (isFirebaseAvailable) {
      try {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .get();
        if (doc.exists && doc.data() != null) {
          final data = doc.data()!;
          final user = UserModel(
            uid: userId,
            name: data['name']?.toString() ?? '',
            email: data['email']?.toString() ?? '',
            createdAt: (data['createdAt'] is Timestamp)
                ? (data['createdAt'] as Timestamp).toDate()
                : (data['createdAt'] != null
                      ? DateTime.tryParse(data['createdAt'].toString()) ??
                            DateTime.now()
                      : DateTime.now()),
            themeMode: data['themeMode']?.toString() ?? 'system',
          );

          // Update local cache
          await hiveService.putSetting(
            AppConstants.keyCachedUser,
            user.toJson(),
          );
          await hiveService.putSetting(
            AppConstants.keyThemeMode,
            user.themeMode,
          );
          return user;
        }
      } catch (e) {
        // Fallback to local cache if Firestore fetch fails
      }
    }

    // Return cached user profile
    final raw = hiveService.getSetting(AppConstants.keyCachedUser);
    if (raw is Map) {
      return UserModel.fromJson(Map<String, dynamic>.from(raw));
    }

    throw const CacheException('No profile found locally or remotely.');
  }

  /// Saves or creates a user profile document in Firestore and local Hive cache.
  Future<void> saveUserProfile(UserModel user) async {
    // 1. Save locally
    await hiveService.putSetting(AppConstants.keyCachedUser, user.toJson());
    await hiveService.putSetting(AppConstants.keyThemeMode, user.themeMode);

    // 2. Sync to Firestore if available
    if (isFirebaseAvailable) {
      try {
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'name': user.name,
          'email': user.email,
          'createdAt': Timestamp.fromDate(user.createdAt),
          'themeMode': user.themeMode,
        }, SetOptions(merge: true));
      } catch (e) {
        // Graceful continuation with local save
      }
    }
  }

  /// Updates preferred theme mode ('system', 'light', 'dark') in Firestore and local storage.
  Future<void> updateThemeMode({
    required String userId,
    required String themeMode,
  }) async {
    await hiveService.putSetting(AppConstants.keyThemeMode, themeMode);

    final raw = hiveService.getSetting(AppConstants.keyCachedUser);
    if (raw is Map) {
      final user = UserModel.fromJson(Map<String, dynamic>.from(raw))
          .copyWith(themeMode: themeMode);
      await hiveService.putSetting(AppConstants.keyCachedUser, user.toJson());
    }

    if (isFirebaseAvailable && userId.isNotEmpty) {
      try {
        await FirebaseFirestore.instance.collection('users').doc(userId).set({
          'themeMode': themeMode,
        }, SetOptions(merge: true));
      } catch (_) {}
    }
  }

  /// Updates user profile display name across Firestore and local storage.
  Future<UserModel> updateProfileName({
    required String userId,
    required String name,
  }) async {
    final raw = hiveService.getSetting(AppConstants.keyCachedUser);
    UserModel user;
    if (raw is Map) {
      user = UserModel.fromJson(Map<String, dynamic>.from(raw))
          .copyWith(name: name);
    } else {
      user = UserModel(
        uid: userId,
        name: name,
        email: '',
        createdAt: DateTime.now(),
      );
    }

    await saveUserProfile(user);
    return user;
  }
}

/// Riverpod provider for [ProfileRepository].
final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  final hive = ref.watch(hiveServiceProvider);
  return ProfileRepository(hiveService: hive);
});
