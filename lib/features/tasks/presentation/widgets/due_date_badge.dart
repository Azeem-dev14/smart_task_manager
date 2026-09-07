import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Reusable badge widget indicating a task's due date with automatic overdue styling.
class DueDateBadge extends StatelessWidget {
  /// The target deadline timestamp.
  final DateTime dueDate;

  /// Whether the task is already completed (suppresses overdue alert).
  final bool isCompleted;

  /// Constructs a [DueDateBadge].
  const DueDateBadge({
    super.key,
    required this.dueDate,
    this.isCompleted = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isOverdue = dueDate.isBefore(DateTime.now()) && !isCompleted;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isOverdue
            ? Colors.red.withValues(alpha: 0.12)
            : theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
        border: isOverdue ? Border.all(color: Colors.red.shade300) : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.access_time_rounded,
            size: 12,
            color: isOverdue
                ? Colors.red.shade700
                : theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 4),
          Text(
            DateFormat('MMM d, h:mm a').format(dueDate),
            style: TextStyle(
              fontSize: 11,
              fontWeight: isOverdue ? FontWeight.w600 : FontWeight.normal,
              color: isOverdue
                  ? Colors.red.shade700
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
