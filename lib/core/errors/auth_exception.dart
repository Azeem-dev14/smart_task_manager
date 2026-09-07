import 'package:smart_task_manager/core/errors/app_exception.dart';

/// Exception thrown during user authentication and authorization flows.
class AuthException extends AppException {
  /// Creates an [AuthException] with a user-friendly message.
  const AuthException(
    super.message, {
    super.code,
    super.originalError,
  });

  /// Factory helper that maps Firebase Auth error codes into human-friendly messages.
  factory AuthException.fromFirebaseCode(String code, [String? fallbackMessage]) {
    switch (code) {
      case 'user-not-found':
        return const AuthException(
          'No account found with this email address.',
          code: 'user-not-found',
        );
      case 'wrong-password':
        return const AuthException(
          'Incorrect password. Please try again.',
          code: 'wrong-password',
        );
      case 'invalid-email':
        return const AuthException(
          'The provided email address is invalid.',
          code: 'invalid-email',
        );
      case 'email-already-in-use':
        return const AuthException(
          'An account already exists with this email.',
          code: 'email-already-in-use',
        );
      case 'weak-password':
        return const AuthException(
          'Password is too weak. Please use at least 6 characters.',
          code: 'weak-password',
        );
      case 'user-disabled':
        return const AuthException(
          'This user account has been disabled.',
          code: 'user-disabled',
        );
      case 'operation-not-allowed':
        return const AuthException(
          'Email and password sign-in is not enabled.',
          code: 'operation-not-allowed',
        );
      case 'network-request-failed':
        return const AuthException(
          'Network error during authentication. Check your internet connection.',
          code: 'network-request-failed',
        );
      case 'too-many-requests':
        return const AuthException(
          'Too many unsuccessful attempts. Please try again in a few moments.',
          code: 'too-many-requests',
        );
      default:
        return AuthException(
          fallbackMessage ?? 'Authentication failed: $code',
          code: code,
        );
    }
  }
}
