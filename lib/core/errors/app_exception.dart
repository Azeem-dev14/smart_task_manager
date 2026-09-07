/// Base exception class for all application errors across domains.
///
/// Implements standard [Exception] contract and encapsulates a human-readable
/// [message], an optional machine-readable [code], and the [originalError] if any.
abstract class AppException implements Exception {
  /// Human-readable description of the error suitable for user display.
  final String message;

  /// Optional machine-readable error code (e.g. Firebase or HTTP code).
  final String? code;

  /// Underlying raw error or exception object captured during failure.
  final dynamic originalError;

  /// Creates a new [AppException] instance.
  const AppException(
    this.message, {
    this.code,
    this.originalError,
  });

  @override
  String toString() => message;
}
