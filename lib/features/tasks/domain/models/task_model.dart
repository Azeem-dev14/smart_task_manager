import 'package:drift/drift.dart' as drift;
import 'package:smart_task_manager/core/database/app_database.dart';
import 'package:smart_task_manager/features/tasks/domain/models/task_category.dart';
import 'package:smart_task_manager/features/tasks/domain/models/task_priority.dart';

export '../mappers/task_entry_mapper.dart';
export 'task_category.dart';
export 'task_priority.dart';

/// Core domain entity representing a Task in the Smart Task Manager application.
///
/// Encapsulates all data attributes required by the OpenAPI backend as well as
/// local metadata needed for offline-first conflict-free synchronization.
class TaskModel {
  final int id;
  final int? localId;
  final String userId;
  final String title;
  final String? description;
  final bool isCompleted;
  final DateTime? dueDate;
  final TaskPriority priority;
  final TaskCategory category;
  final DateTime createdAt;
  final DateTime updatedAt;

  // Local sync metadata
  final bool isPendingSync;
  final String syncStatus;
  final DateTime? lastSyncedAt;

  const TaskModel({
    required this.id,
    this.localId,
    required this.userId,
    required this.title,
    this.description,
    this.isCompleted = false,
    this.dueDate,
    this.priority = TaskPriority.medium,
    this.category = TaskCategory.work,
    required this.createdAt,
    required this.updatedAt,
    this.isPendingSync = false,
    this.syncStatus = SyncStatus.synced,
    this.lastSyncedAt,
  });

  /// Creates a copy of this [TaskModel] with specified fields replaced.
  ///
  /// Because `null` means "leave unchanged", the nullable [description] and
  /// [dueDate] fields are cleared with the explicit [clearDescription] and
  /// [clearDueDate] flags — otherwise removing a task's due date would be
  /// indistinguishable from not touching it.
  TaskModel copyWith({
    int? id,
    int? localId,
    String? userId,
    String? title,
    String? description,
    bool? isCompleted,
    DateTime? dueDate,
    TaskPriority? priority,
    TaskCategory? category,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isPendingSync,
    String? syncStatus,
    DateTime? lastSyncedAt,
    bool clearDescription = false,
    bool clearDueDate = false,
  }) {
    return TaskModel(
      id: id ?? this.id,
      localId: localId ?? this.localId,
      userId: userId ?? this.userId,
      title: title ?? this.title,
      description: clearDescription ? null : (description ?? this.description),
      isCompleted: isCompleted ?? this.isCompleted,
      dueDate: clearDueDate ? null : (dueDate ?? this.dueDate),
      priority: priority ?? this.priority,
      category: category ?? this.category,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isPendingSync: isPendingSync ?? this.isPendingSync,
      syncStatus: syncStatus ?? this.syncStatus,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
    );
  }

  /// Serializes the model into a JSON map (including local sync metadata).
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'local_id': localId,
      'user_id': userId,
      'title': title,
      'description': description,
      'is_completed': isCompleted,
      'due_date': dueDate?.toIso8601String(),
      'priority': priority.value,
      'category': category.value,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'is_pending_sync': isPendingSync,
      'sync_status': syncStatus,
      'last_synced_at': lastSyncedAt?.toIso8601String(),
    };
  }

  /// Serializes payload matching the FastAPI `/tasks/` POST & PUT body schema.
  Map<String, dynamic> toApiCreateJson() {
    return {
      'title': title,
      'description': description,
      'is_completed': isCompleted,
      'due_date': dueDate?.toIso8601String(),
      'priority': priority.value,
      'category': category.value,
    };
  }

  /// Deserializes a [TaskModel] from a JSON map (handles both API and local cache formats).
  factory TaskModel.fromJson(Map<String, dynamic> json) {
    return TaskModel(
      id: json['id'] is int ? json['id'] : int.parse(json['id'].toString()),
      localId: json['local_id'] as int?,
      userId: json['user_id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      description: json['description']?.toString(),
      isCompleted: json['is_completed'] == true,
      dueDate: json['due_date'] != null ? DateTime.tryParse(json['due_date'].toString()) : null,
      priority: TaskPriority.fromString(json['priority']?.toString()),
      category: TaskCategory.fromString(json['category']?.toString()),
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      isPendingSync: json['is_pending_sync'] == true ||
          (json['sync_status'] != null && json['sync_status'] != SyncStatus.synced),
      syncStatus: json['sync_status']?.toString() ?? SyncStatus.synced,
      lastSyncedAt: json['last_synced_at'] != null
          ? DateTime.tryParse(json['last_synced_at'].toString())
          : null,
    );
  }

  /// Converts this model into a Drift SQLite companion for database insertion.
  TasksTableCompanion toCompanion({String status = SyncStatus.synced}) {
    return TasksTableCompanion.insert(
      serverId: id > 0 ? drift.Value(id) : const drift.Value.absent(),
      userId: userId,
      title: title,
      description: drift.Value(description),
      isCompleted: drift.Value(isCompleted),
      dueDate: drift.Value(dueDate),
      priority: drift.Value(priority.value),
      category: drift.Value(category.value),
      createdAt: createdAt,
      updatedAt: updatedAt,
      syncStatus: drift.Value(status),
      lastSyncedAt: status == SyncStatus.synced ? drift.Value(DateTime.now()) : const drift.Value.absent(),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TaskModel &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          localId == other.localId &&
          userId == other.userId &&
          title == other.title &&
          isCompleted == other.isCompleted &&
          syncStatus == other.syncStatus;

  @override
  int get hashCode => id.hashCode ^ (localId ?? 0).hashCode ^ userId.hashCode ^ isCompleted.hashCode;
}
