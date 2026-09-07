import 'package:flutter/material.dart';
import 'package:smart_task_manager/core/errors/app_exceptions.dart';

/// Reusable full-page error view with categorized icons, user-friendly messages, and retry actions.
class ErrorView extends StatelessWidget {
  /// The underlying error or exception object to display.
  final Object error;

  /// Optional callback executed when user taps the 'Try Again' button.
  final VoidCallback? onRetry;

  /// Constructs an [ErrorView].
  const ErrorView({
    super.key,
    required this.error,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    IconData icon = Icons.error_outline;
    String title = 'Something went wrong';
    String message = error.toString();
    Color iconColor = theme.colorScheme.error;

    if (error is NetworkException) {
      icon = Icons.wifi_off_rounded;
      title = 'Network Connection Issue';
      iconColor = Colors.orange.shade700;
      message = (error as NetworkException).message;
    } else if (error is ServerException) {
      icon = Icons.cloud_off_rounded;
      final serverErr = error as ServerException;
      title = 'Server Error ${serverErr.statusCode != null ? "(${serverErr.statusCode})" : ""}';
      message = serverErr.message;
    } else if (error is AuthException) {
      icon = Icons.lock_outline_rounded;
      title = 'Authentication Error';
      message = (error as AuthException).message;
    } else if (error is CacheException) {
      icon = Icons.storage_rounded;
      title = 'Storage Error';
      message = (error as CacheException).message;
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 50, color: iconColor),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 24),
              FilledButton.tonalIcon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Try Again'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Utility method to present a standardized floating error snackbar for any [error].
  static void showSnackBar(BuildContext context, Object error) {
    final theme = Theme.of(context);
    String message = error.toString();
    IconData icon = Icons.error_outline;
    Color bg = theme.colorScheme.errorContainer;
    Color textCol = theme.colorScheme.onErrorContainer;

    if (error is NetworkException) {
      icon = Icons.wifi_off_rounded;
      bg = Colors.amber.shade900;
      textCol = Colors.white;
      message = error.message;
    } else if (error is ServerException) {
      icon = Icons.cloud_off_rounded;
      message = error.message;
    } else if (error is AuthException) {
      icon = Icons.lock_outline_rounded;
      message = error.message;
    } else if (error is CacheException) {
      icon = Icons.storage_rounded;
      message = error.message;
    }

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: bg,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        content: Row(
          children: [
            Icon(icon, color: textCol, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: textCol, fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
