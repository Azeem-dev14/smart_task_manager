import 'package:smart_task_manager/core/errors/app_exception.dart';

/// Exception thrown during local persistence operations (Drift SQLite or Hive storage).
class CacheException extends AppException {
  /// Creates a [CacheException] with an error message and optional root error.
  const CacheException(
    super.message, {
    super.code,
    super.originalError,
  });
}
