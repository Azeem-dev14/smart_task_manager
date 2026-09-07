import 'package:smart_task_manager/core/errors/app_exception.dart';

/// Exception thrown when remote server returns an error response (4xx, 5xx, or invalid schema).
class ServerException extends AppException {
  /// The HTTP status code returned by the server, if available.
  final int? statusCode;

  /// Creates a [ServerException] with an error message, HTTP status code, and optional root error.
  const ServerException(
    super.message, {
    this.statusCode,
    super.code,
    super.originalError,
  });
}
