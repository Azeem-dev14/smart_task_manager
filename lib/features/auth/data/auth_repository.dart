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
  StreamSubscription<User?>? _firebaseSubscription;

  UserModel? _currentUser;

  /// Constructs an [AuthRepository] and initializes authentication state listening.
  AuthRepository({required this.hiveService}) {
    _currentUser = _readCachedUser();
    _listenToFirebaseAuthState();
  }

  /// The signed-in user, or `null` when signed out.
  ///
  /// Resolved synchronously from the local cache at construction time so the
  /// first frame can route without waiting on a stream.
  UserModel? get currentUser => _currentUser;

  /// Stream of authentication state transitions emitting [UserModel] or `null`.
  ///
  /// Replays the current value to each new subscriber, so a listener attaching
  /// after startup is never left waiting for the next transition.
  Stream<UserModel?> get authStateChanges async* {
    yield _currentUser;
    yield* _authStateController.stream;
  }

  /// Whether Firebase has been initialized successfully in the current process.
  bool get isFirebaseAvailable => Firebase.apps.isNotEmpty;

  void _listenToFirebaseAuthState() {
    if (!isFirebaseAvailable) return;

    _firebaseSubscription = FirebaseAuth.instance.authStateChanges().listen((User? user) async {
      if (user == null) {
        // The Firebase session ended (sign out elsewhere, deleted or disabled
        // account, revoked token). The local cache must not outlive it.
        if (_currentUser != null) await _clearSession();
        return;
      }

      // Keep the richer cached profile when it belongs to the same account.
      if (_currentUser?.uid == user.uid) return;

      _emit(
        UserModel(
          uid: user.uid,
          name: user.displayName ?? user.email?.split('@').first ?? 'User',
          email: user.email ?? '',
          createdAt: user.metadata.creationTime ?? DateTime.now(),
        ),
      );
    });
  }

  UserModel? _readCachedUser() {
    final raw = hiveService.getSetting(AppConstants.keyCachedUser);
    if (raw is Map) {
      return UserModel.fromJson(Map<String, dynamic>.from(raw));
    }
    return null;
  }

  void _emit(UserModel? user) {
    _currentUser = user;
    if (!_authStateController.isClosed) {
      _authStateController.add(user);
    }
  }

  /// Restores a persistent login session on app start.
  ///
  /// When Firebase is available its own session is authoritative: a cached
  /// profile without a live Firebase session is stale and gets cleared.
  Future<UserModel?> restoreSession() async {
    if (!isFirebaseAvailable) return _currentUser;

    final firebaseUser = FirebaseAuth.instance.currentUser;
    if (firebaseUser == null) {
      if (_currentUser != null) await _clearSession();
      return null;
    }

    final cached = _currentUser;
    if (cached != null && cached.uid == firebaseUser.uid) return cached;

    final restored = UserModel(
      uid: firebaseUser.uid,
      name: firebaseUser.displayName ?? firebaseUser.email?.split('@').first ?? 'User',
      email: firebaseUser.email ?? '',
      createdAt: firebaseUser.metadata.creationTime ?? DateTime.now(),
    );
    await cacheUser(restored);
    return restored;
  }

  /// Writes [user] to local storage and broadcasts it to listeners.
  Future<void> cacheUser(UserModel user) async {
    await hiveService.putSetting(AppConstants.keyCachedUser, user.toJson());
    await hiveService.putSetting(AppConstants.keyCachedUid, user.uid);
    _emit(user);
  }

  Future<void> _clearSession() async {
    await hiveService.removeSetting(AppConstants.keyCachedUser);
    await hiveService.removeSetting(AppConstants.keyCachedUid);
    _emit(null);
  }

  /// Registers a new user account with [name], [email], and [password].
  Future<UserModel> register({
    required String name,
    required String email,
    required String password,
  }) async {
    if (!isFirebaseAvailable) return _registerLocally(name: name, email: email);

    try {
      final credential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(email: email.trim(), password: password)
          .timeout(AppConstants.firebaseTimeout);

      final user = credential.user;
      if (user == null) {
        throw const AuthException('Registration failed. User was not created.');
      }

      await user.updateDisplayName(name.trim()).timeout(AppConstants.firebaseTimeout);

      final userModel = UserModel(
        uid: user.uid,
        name: name.trim(),
        email: user.email ?? email.trim(),
        createdAt: user.metadata.creationTime ?? DateTime.now(),
      );

      await cacheUser(userModel);
      return userModel;
    } on FirebaseAuthException catch (e) {
      throw AuthException.fromFirebaseCode(e.code, e.message);
    } on TimeoutException {
      // The Firebase SDKs enforce no timeout of their own, so without this a
      // device with no route to Firebase would leave the caller awaiting
      // forever instead of failing — the register button stuck spinning.
      throw AuthException.fromFirebaseCode('network-request-failed');
    } catch (e) {
      if (e is AppException) rethrow;
      throw AuthException('Could not complete registration.', originalError: e);
    }
  }

  /// Signs in an existing user with [email] and [password].
  Future<UserModel> login({
    required String email,
    required String password,
  }) async {
    if (!isFirebaseAvailable) return _loginLocally(email: email);

    try {
      final credential = await FirebaseAuth.instance
          .signInWithEmailAndPassword(email: email.trim(), password: password)
          .timeout(AppConstants.firebaseTimeout);

      final user = credential.user;
      if (user == null) {
        throw const AuthException('User credentials not found.');
      }

      final userModel = UserModel(
        uid: user.uid,
        name: user.displayName ?? user.email?.split('@').first ?? 'User',
        email: user.email ?? email.trim(),
        createdAt: user.metadata.creationTime ?? DateTime.now(),
      );

      await cacheUser(userModel);
      return userModel;
    } on FirebaseAuthException catch (e) {
      throw AuthException.fromFirebaseCode(e.code, e.message);
    } on TimeoutException {
      throw AuthException.fromFirebaseCode('network-request-failed');
    } catch (e) {
      if (e is AppException) rethrow;
      throw AuthException('Could not sign you in.', originalError: e);
    }
  }

  /// Signs out the active user and clears the local session cache.
  Future<void> logout() async {
    if (isFirebaseAvailable) {
      try {
        await FirebaseAuth.instance.signOut().timeout(AppConstants.firebaseTimeout);
      } on FirebaseAuthException catch (e) {
        throw AuthException.fromFirebaseCode(e.code, e.message);
      } on TimeoutException {
        throw AuthException.fromFirebaseCode('network-request-failed');
      }
    }
    await _clearSession();
  }

  /// Offline fallback registration used when Firebase is not configured.
  Future<UserModel> _registerLocally({required String name, required String email}) async {
    final userModel = UserModel(
      uid: 'local_${email.trim().toLowerCase().hashCode.abs()}',
      name: name.trim(),
      email: email.trim(),
      createdAt: DateTime.now(),
    );
    await cacheUser(userModel);
    return userModel;
  }

  /// Offline fallback sign-in used when Firebase is not configured.
  Future<UserModel> _loginLocally({required String email}) async {
    final cached = _readCachedUser();
    if (cached != null && cached.email.toLowerCase() == email.trim().toLowerCase()) {
      await cacheUser(cached);
      return cached;
    }

    final fallbackUser = UserModel(
      uid: 'local_${email.trim().toLowerCase().hashCode.abs()}',
      name: email.split('@').first,
      email: email.trim(),
      createdAt: DateTime.now(),
    );
    await cacheUser(fallbackUser);
    return fallbackUser;
  }

  /// Disposes internal subscriptions and the broadcast stream controller.
  void dispose() {
    _firebaseSubscription?.cancel();
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

/// The currently signed-in user, or `null` when signed out.
///
/// Seeded synchronously from the cached session and kept current by the
/// repository's auth state stream, so widgets and controllers can simply
/// `ref.watch` it and rebuild when the account changes.
final currentUserProvider = NotifierProvider<CurrentUserNotifier, UserModel?>(
  CurrentUserNotifier.new,
);

/// Notifier tracking the active [UserModel] across sign-in and sign-out.
class CurrentUserNotifier extends Notifier<UserModel?> {
  @override
  UserModel? build() {
    final repo = ref.watch(authRepositoryProvider);
    final subscription = repo.authStateChanges.listen((user) => state = user);
    ref.onDispose(subscription.cancel);
    return repo.currentUser;
  }
}
