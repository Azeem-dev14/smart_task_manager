import 'package:smart_task_manager/core/database/app_database.dart';
import 'package:smart_task_manager/features/tasks/domain/models/task_model.dart';

/// Extension providing bidirectional translation between Drift SQLite [TaskEntry]
/// and immutable domain [TaskModel].
extension TaskEntryMapper on TaskEntry {
  /// Maps a Drift SQLite [TaskEntry] entity to a pure domain [TaskModel].
  TaskModel toModel() {
    return TaskModel(
      id: serverId ?? id,
      localId: id,
      userId: userId,
      title: title,
      description: description,
      isCompleted: isCompleted,
      dueDate: dueDate,
      priority: TaskPriority.fromString(priority),
      category: TaskCategory.fromString(category),
      createdAt: createdAt,
      updatedAt: updatedAt,
      isPendingSync: syncStatus != SyncStatus.synced,
      syncStatus: syncStatus,
      lastSyncedAt: lastSyncedAt,
    );
  }
}
