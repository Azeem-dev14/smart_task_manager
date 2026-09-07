import 'package:smart_task_manager/core/errors/app_exception.dart';

/// Fallback exception used when a failure cannot be classified as a
/// network, server, cache or authentication problem.
///
/// Having a concrete leaf type means every failure surfacing in the UI is an
/// [AppException], so presentation widgets can always switch on the error type.
class UnknownException extends AppException {
  /// Creates an [UnknownException].
  const UnknownException([
    super.message = 'Something went wrong. Please try again.',
    String? code,
    dynamic originalError,
  ]) : super(code: code, originalError: originalError);
}
