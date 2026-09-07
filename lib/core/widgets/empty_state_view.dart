import 'package:flutter/material.dart';
import 'package:smart_task_manager/core/theme/text_styles.dart';

/// Reusable presentation component displayed when task lists or search queries have no items.
class EmptyStateView extends StatelessWidget {
  /// The center illustration icon.
  final IconData icon;

  /// Main headline text.
  final String title;

  /// Secondary guidance description text.
  final String description;

  /// Optional call-to-action button text.
  final String? actionLabel;

  /// Callback executed when the call-to-action button is pressed.
  final VoidCallback? onAction;

  /// Constructs an [EmptyStateView].
  const EmptyStateView({
    super.key,
    this.icon = Icons.task_alt_outlined,
    required this.title,
    required this.description,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 54,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: context.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              description,
              textAlign: TextAlign.center,
              style: context.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.add),
                label: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
