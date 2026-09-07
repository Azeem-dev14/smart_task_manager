import 'package:flutter/material.dart';
import 'package:smart_task_manager/features/tasks/domain/models/task_category.dart';

/// Reusable badge widget indicating a task's category.
class CategoryBadge extends StatelessWidget {
  /// The task category to display.
  final TaskCategory category;

  /// Constructs a [CategoryBadge].
  const CategoryBadge({super.key, required this.category});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        category.value,
        style: TextStyle(
          fontSize: 11,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
