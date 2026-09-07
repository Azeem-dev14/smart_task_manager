import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smart_task_manager/core/constants/app_constants.dart';
import 'package:smart_task_manager/core/errors/app_exceptions.dart';
import 'package:smart_task_manager/core/storage/hive_service.dart';
import 'package:smart_task_manager/features/auth/domain/user_model.dart';

/// Repository handling user authentication with Firebase Auth, local session caching,
/// and offline mock fallback support when running without Firebase credentials.
class AuthRepository {
  /// Local key-value storage service for session persistence.
  final HiveService hiveService;
  final _authStateController = StreamController<UserModel?>.broadcast();

  /// Constructs an [AuthRepository] and initializes authentication state listening.
  AuthRepository({required this.hiveService}) {
    _initAuthState();
  }

  /// Stream of authentication state transitions emitting [UserModel] or `null`.
  Stream<UserModel?> get authStateChanges => _authStateController.stream;

  /// Whether Firebase has been initialized successfully in the current process.
  bool get isFirebaseAvailable => Firebase.apps.isNotEmpty;

  void _initAuthState() {
    if (isFirebaseAvailable) {
      FirebaseAuth.instance.authStateChanges().listen((User? user) {
        if (user == null) {
          _authStateController.add(null);
        } else {
          final cached = getCachedUser();
          if (cached != null && cached.uid == user.uid) {
            _authStateController.add(cached);
          } else {
            final u = UserModel(
              uid: user.uid,
              name: user.displayName ?? user.email?.split('@').first ?? 'User',
              email: user.email ?? '',
              createdAt: DateTime.now(),
            );
            _authStateController.add(u);
          }
        }
      });
    } else {
      // Local persistent session fallback
      final cached = getCachedUser();
      _authStateController.add(cached);
    }
  }

  /// Reads the currently cached [UserModel] from local Hive storage.
  UserModel? getCachedUser() {
    final raw = hiveService.getSetting(AppConstants.keyCachedUser);
    if (raw is Map) {
      return UserModel.fromJson(Map<String, dynamic>.from(raw));
    }
    return null;
  }

  /// Writes [user] to local Hive storage and broadcasts to listeners.
  Future<void> cacheUser(UserModel user) async {
    await hiveService.putSetting(AppConstants.keyCachedUser, user.toJson());
    await hiveService.putSetting(AppConstants.keyCachedUid, user.uid);
    _authStateController.add(user);
  }

  /// Registers a new user account with [name], [email], and [password].
  Future<UserModel> register({
    required String name,
    required String email,
    required String password,
  }) async {
    if (isFirebaseAvailable) {
      try {
        final credential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: email.trim(),
          password: password,
        );

        final user = credential.user;
        if (user == null) {
          throw const AuthException('Registration failed. User was not created.');
        }

        await user.updateDisplayName(name.trim());

        final userModel = UserModel(
          uid: user.uid,
          name: name.trim(),
          email: user.email ?? email.trim(),
          createdAt: DateTime.now(),
        );

        await cacheUser(userModel);
        return userModel;
      } on FirebaseAuthException catch (e) {
        throw AuthException.fromFirebaseCode(e.code, e.message);
      } catch (e) {
        if (e is AppException) rethrow;
        throw AuthException('Failed to register: $e', originalError: e);
      }
    } else {
      // Offline / Local Mock Fallback
      await Future.delayed(const Duration(milliseconds: 600));
      final uid = 'user_${DateTime.now().millisecondsSinceEpoch}';
      final userModel = UserModel(
        uid: uid,
        name: name.trim(),
        email: email.trim(),
        createdAt: DateTime.now(),
      );

      await cacheUser(userModel);
      return userModel;
    }
  }

  /// Signs in an existing user with [email] and [password].
  Future<UserModel> login({
    required String email,
    required String password,
  }) async {
    if (isFirebaseAvailable) {
      try {
        final credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email.trim(),
          password: password,
        );

        final user = credential.user;
        if (user == null) {
          throw const AuthException('User credentials not found.');
        }

        final userModel = UserModel(
          uid: user.uid,
          name: user.displayName ?? user.email?.split('@').first ?? 'User',
          email: user.email ?? email.trim(),
          createdAt: DateTime.now(),
        );

        await cacheUser(userModel);
        return userModel;
      } on FirebaseAuthException catch (e) {
        throw AuthException.fromFirebaseCode(e.code, e.message);
      } catch (e) {
        if (e is AppException) rethrow;
        throw AuthException('Failed to login: $e', originalError: e);
      }
    } else {
      // Offline / Local Fallback
      await Future.delayed(const Duration(milliseconds: 600));
      final cached = getCachedUser();
      if (cached != null && cached.email.toLowerCase() == email.trim().toLowerCase()) {
        _authStateController.add(cached);
        return cached;
      }

      final fallbackUser = UserModel(
        uid: 'user_${email.trim().hashCode.abs()}',
        name: email.split('@').first,
        email: email.trim(),
        createdAt: DateTime.now(),
      );

      await cacheUser(fallbackUser);
      return fallbackUser;
    }
  }

  /// Signs out the active user and clears local session cache.
  Future<void> logout() async {
    if (isFirebaseAvailable) {
      await FirebaseAuth.instance.signOut();
    }
    await hiveService.putSetting(AppConstants.keyCachedUser, null);
    await hiveService.putSetting(AppConstants.keyCachedUid, null);
    _authStateController.add(null);
  }

  /// Disposes internal broadcast stream controller.
  void dispose() {
    _authStateController.close();
  }
}

/// Provider for the singleton [AuthRepository].
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final hiveService = ref.watch(hiveServiceProvider);
  final repo = AuthRepository(hiveService: hiveService);
  ref.onDispose(repo.dispose);
  return repo;
});

/// Stream provider listening to real-time authentication session changes.
final authStateProvider = StreamProvider<UserModel?>((ref) {
  final repo = ref.watch(authRepositoryProvider);
  return repo.authStateChanges;
});
