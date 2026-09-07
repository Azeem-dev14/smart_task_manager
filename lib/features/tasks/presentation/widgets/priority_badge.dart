import 'package:flutter/material.dart';
import 'package:smart_task_manager/core/theme/app_theme.dart';
import 'package:smart_task_manager/features/tasks/domain/models/task_priority.dart';

/// Reusable badge widget indicating a task's priority level with color-coded dot and border.
class PriorityBadge extends StatelessWidget {
  /// The priority level to display.
  final TaskPriority priority;

  /// Constructs a [PriorityBadge].
  const PriorityBadge({super.key, required this.priority});

  /// Resolves the theme color associated with [priority].
  static Color getColor(TaskPriority priority) {
    switch (priority) {
      case TaskPriority.high:
        return AppTheme.priorityHigh;
      case TaskPriority.medium:
        return AppTheme.priorityMedium;
      case TaskPriority.low:
        return AppTheme.priorityLow;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = getColor(priority);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(radius: 3, backgroundColor: color),
          const SizedBox(width: 4),
          Text(
            priority.value,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
