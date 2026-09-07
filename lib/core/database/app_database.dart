import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:smart_task_manager/core/constants/sync_status.dart';

export '../constants/sync_status.dart';

part 'app_database.g.dart';

/// Drift SQLite table definition representing the local tasks store.
///
/// This table serves as the Single Source of Truth for the entire application,
/// supporting offline work execution, optimistic updates, and background sync.
@DataClassName('TaskEntry')
class TasksTable extends Table {
  /// Local auto-incremented SQLite primary key.
  IntColumn get id => integer().autoIncrement()();

  /// Remote backend ID returned by FastAPI (`null` until synced).
  IntColumn get serverId => integer().nullable()();

  /// User identifier who owns this task.
  TextColumn get userId => text()();

  /// The title of the task.
  TextColumn get title => text()();

  /// Optional description or notes for the task.
  TextColumn get description => text().nullable()();

  /// Completion status flag.
  BoolColumn get isCompleted => boolean().withDefault(const Constant(false))();

  /// Optional deadline or scheduled date/time.
  DateTimeColumn get dueDate => dateTime().nullable()();

  /// Priority string ('Low', 'Medium', 'High').
  TextColumn get priority => text().withDefault(const Constant('Medium'))();

  /// Category string ('Work', 'Personal', etc.).
  TextColumn get category => text().withDefault(const Constant('Work'))();

  /// Timestamp when the record was created locally.
  DateTimeColumn get createdAt => dateTime()();

  /// Timestamp when the record was last modified.
  DateTimeColumn get updatedAt => dateTime()();

  /// Current synchronization lifecycle state (synced, pending_create, pending_update, pending_delete).
  TextColumn get syncStatus => text().withDefault(const Constant(SyncStatus.synced))();

  /// Timestamp when this record was last successfully synced with the server.
  DateTimeColumn get lastSyncedAt => dateTime().nullable()();
}

/// Local Drift SQLite database engine.
///
/// Provides reactive streams, transactional queries, and offline mutation primitives.
@DriftDatabase(tables: [TasksTable])
class AppDatabase extends _$AppDatabase {
  /// Constructs the database using a background lazy connection.
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 1;

  /// Emits a real-time reactive stream of non-deleted tasks for a given [userId].
  ///
  /// This query is the primary reactive data feed for the task list UI, sorted by
  /// creation timestamp in descending order.
  Stream<List<TaskEntry>> watchActiveTasks(String userId) {
    return (select(tasksTable)
          ..where((tbl) =>
              tbl.userId.equals(userId) &
              tbl.syncStatus.isNotValue(SyncStatus.pendingDelete))
          ..orderBy([
            (tbl) => OrderingTerm.desc(tbl.createdAt),
          ]))
        .watch();
  }

  /// Fetches a one-time list of all active (non-deleted) tasks for [userId].
  Future<List<TaskEntry>> getActiveTasks(String userId) {
    return (select(tasksTable)
          ..where((tbl) =>
              tbl.userId.equals(userId) &
              tbl.syncStatus.isNotValue(SyncStatus.pendingDelete))
          ..orderBy([
            (tbl) => OrderingTerm.desc(tbl.createdAt),
          ]))
        .get();
  }

  /// Returns all local records that have unsaved changes awaiting remote synchronization.
  Future<List<TaskEntry>> getPendingSyncTasks(String userId) {
    return (select(tasksTable)
          ..where((tbl) =>
              tbl.userId.equals(userId) &
              tbl.syncStatus.isNotValue(SyncStatus.synced)))
        .get();
  }

  /// Inserts a new task companion into the local database.
  ///
  /// Returns the newly generated local integer primary key.
  Future<int> executeCreateTask(TasksTableCompanion companion) {
    return into(tasksTable).insert(companion);
  }

  /// Updates an existing task in the local database and marks it for sync.
  Future<bool> executeUpdateTask(TaskEntry task) {
    final newStatus = (task.syncStatus == SyncStatus.pendingCreate)
        ? SyncStatus.pendingCreate
        : SyncStatus.pendingUpdate;

    return update(tasksTable).replace(
      task.copyWith(
        syncStatus: newStatus,
        updatedAt: DateTime.now(),
      ),
    );
  }

  /// Toggles the completion state of [task] and flags it for background sync.
  Future<bool> executeToggleCompletion(TaskEntry task) {
    final newStatus = (task.syncStatus == SyncStatus.pendingCreate)
        ? SyncStatus.pendingCreate
        : SyncStatus.pendingUpdate;

    return update(tasksTable).replace(
      task.copyWith(
        isCompleted: !task.isCompleted,
        syncStatus: newStatus,
        updatedAt: DateTime.now(),
      ),
    );
  }

  /// Executes local deletion of [task].
  ///
  /// If the task was never sent to the server (created offline), it is removed immediately.
  /// Otherwise, it is soft-deleted with [SyncStatus.pendingDelete] until the remote
  /// delete API request succeeds.
  Future<void> executeDeleteTask(TaskEntry task) async {
    if (task.serverId == null || task.syncStatus == SyncStatus.pendingCreate) {
      await (delete(tasksTable)..where((tbl) => tbl.id.equals(task.id))).go();
    } else {
      await update(tasksTable).replace(
        task.copyWith(
          syncStatus: SyncStatus.pendingDelete,
          updatedAt: DateTime.now(),
        ),
      );
    }
  }

  /// Upserts a task fetched from the remote API into the local database.
  ///
  /// Preserves local uncommitted edits if the record currently has pending mutations.
  Future<void> upsertServerTask({
    required int serverId,
    required String userId,
    required String title,
    String? description,
    required bool isCompleted,
    DateTime? dueDate,
    required String priority,
    required String category,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) async {
    final existing = await (select(tasksTable)
          ..where((tbl) => tbl.serverId.equals(serverId)))
        .getSingleOrNull();

    if (existing != null) {
      // Avoid clobbering pending local edits
      if (existing.syncStatus != SyncStatus.synced) return;

      await update(tasksTable).replace(
        existing.copyWith(
          title: title,
          description: Value(description),
          isCompleted: isCompleted,
          dueDate: Value(dueDate),
          priority: priority,
          category: category,
          updatedAt: updatedAt,
          syncStatus: SyncStatus.synced,
          lastSyncedAt: Value(DateTime.now()),
        ),
      );
    } else {
      await into(tasksTable).insert(
        TasksTableCompanion.insert(
          serverId: Value(serverId),
          userId: userId,
          title: title,
          description: Value(description),
          isCompleted: Value(isCompleted),
          dueDate: Value(dueDate),
          priority: Value(priority),
          category: Value(category),
          createdAt: createdAt,
          updatedAt: updatedAt,
          syncStatus: const Value(SyncStatus.synced),
          lastSyncedAt: Value(DateTime.now()),
        ),
      );
    }
  }

  /// Updates a local record with its newly assigned [serverId] upon successful remote creation.
  Future<void> markTaskSynced({
    required int localId,
    required int serverId,
    required DateTime updatedAt,
  }) async {
    await (update(tasksTable)..where((tbl) => tbl.id.equals(localId))).write(
      TasksTableCompanion(
        serverId: Value(serverId),
        syncStatus: const Value(SyncStatus.synced),
        updatedAt: Value(updatedAt),
        lastSyncedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Permanently removes a task row from SQLite after successful remote deletion.
  Future<void> removePermanently(int localId) async {
    await (delete(tasksTable)..where((tbl) => tbl.id.equals(localId))).go();
  }
}

/// Creates a background-isolated SQLite database file connection.
LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'smart_task_manager.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}

/// Riverpod provider delivering the application's singleton [AppDatabase] instance.
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});
