import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smart_task_manager/core/theme/text_styles.dart';
import 'package:smart_task_manager/core/widgets/app_confirm_dialog.dart';
import 'package:smart_task_manager/features/tasks/domain/models/task_model.dart';
import 'package:smart_task_manager/features/tasks/presentation/controllers/task_list_notifier.dart';
import 'package:smart_task_manager/features/tasks/presentation/widgets/category_badge.dart';
import 'package:smart_task_manager/features/tasks/presentation/widgets/due_date_badge.dart';
import 'package:smart_task_manager/features/tasks/presentation/widgets/priority_badge.dart';
import 'package:smart_task_manager/features/tasks/presentation/widgets/sync_status_badge.dart';
import 'package:smart_task_manager/features/tasks/presentation/screens/task_form_screen.dart';

/// Presentation card displaying a single task item.
///
/// Features completion toggle checkbox, title strike-through, description snippet,
/// reusable badges for priority, category, due date, and sync status, plus an
/// options menu for editing and deletion.
class TaskCard extends ConsumerWidget {
  /// The task domain model represented by this card.
  final TaskModel task;

  /// Constructs a [TaskCard].
  const TaskCard({super.key, required this.task});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => TaskFormScreen.show(context, existingTask: task),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Completion Checkbox — shrink its tap target so the visible
              // box (not an invisible 48dp hit area) is what lines up with
              // the card's padding and the title's first line.
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Checkbox(
                  value: task.isCompleted,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                  onChanged: (_) {
                    ref
                        .read(taskListControllerProvider.notifier)
                        .toggleTaskCompleted(task);
                  },
                ),
              ),
              const SizedBox(width: 10),

              // Task Details Column
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title & Sync Cloud Icon
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            task.title,
                            style: context.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              decoration: task.isCompleted
                                  ? TextDecoration.lineThrough
                                  : TextDecoration.none,
                              color: task.isCompleted
                                  ? theme.colorScheme.onSurface.withValues(
                                      alpha: 0.5,
                                    )
                                  : theme.colorScheme.onSurface,
                            ),
                          ),
                        ),
                        if (task.isPendingSync)
                          Tooltip(
                            message: 'Pending sync with server',
                            child: Padding(
                              padding: const EdgeInsets.only(left: 4.0),
                              child: Icon(
                                Icons.cloud_queue_rounded,
                                size: 16,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          ),
                      ],
                    ),

                    if (task.description != null &&
                        task.description!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        task.description!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: context.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.7,
                          ),
                        ),
                      ),
                    ],

                    const SizedBox(height: 10),

                    // Badges row (Sync, Priority, Category, Due Date)
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        // Reusable Sync Status Badge
                        SyncStatusBadge(isPendingSync: task.isPendingSync),

                        // Reusable Priority Badge
                        PriorityBadge(priority: task.priority),

                        // Reusable Category Badge
                        CategoryBadge(category: task.category),

                        // Reusable Due Date Badge
                        if (task.dueDate != null)
                          DueDateBadge(
                            dueDate: task.dueDate!,
                            isCompleted: task.isCompleted,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),

              // Options Menu (Edit / Delete)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, size: 20),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  onSelected: (action) {
                    if (action == 'edit') {
                      TaskFormScreen.show(context, existingTask: task);
                    } else if (action == 'delete') {
                      _confirmDelete(context, ref);
                    }
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          Icon(Icons.edit_outlined, size: 18),
                          SizedBox(width: 8),
                          Text('Edit'),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(
                            Icons.delete_outline,
                            size: 18,
                            color: Colors.red.shade400,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Delete',
                            style: TextStyle(color: Colors.red.shade400),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Prompts user confirmation before executing task deletion.
  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await AppConfirmDialog.show(
      context,
      title: 'Delete Task?',
      message: 'Are you sure you want to delete "${task.title}"?',
      confirmText: 'Delete',
      isDestructive: true,
    );

    if (confirmed) {
      ref.read(taskListControllerProvider.notifier).deleteTask(task);
    }
  }
}
