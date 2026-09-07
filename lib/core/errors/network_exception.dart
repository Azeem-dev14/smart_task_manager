import 'package:smart_task_manager/core/errors/app_exception.dart';

/// Exception thrown when network connectivity issues occur (timeouts, unreachable host, offline).
class NetworkException extends AppException {
  /// Creates a [NetworkException] with an optional custom message, code, and original error.
  const NetworkException([
    super.message = 'Network connection issue. Please check your internet connection.',
    String? code,
    dynamic originalError,
  ]) : super(code: code, originalError: originalError);
}
