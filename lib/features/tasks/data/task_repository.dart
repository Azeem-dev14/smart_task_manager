import 'dart:developer' as dev;
import 'package:drift/drift.dart' as drift;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smart_task_manager/core/constants/app_constants.dart';
import 'package:smart_task_manager/core/database/app_database.dart';
import 'package:smart_task_manager/core/network/api_client.dart';
import 'package:smart_task_manager/core/network/connectivity_service.dart';
import 'package:smart_task_manager/features/tasks/domain/models/task_model.dart';

/// Repository managing task persistence, reactive streams, optimistic local mutations,
/// and bidirectional synchronization between Drift SQLite and the remote FastAPI backend.
class TaskRepository {
  /// REST API client for backend communication.
  final ApiClient apiClient;

  /// Local Drift SQLite database engine (Single Source of Truth).
  final AppDatabase db;

  /// Network connectivity service for real-time online status checks.
  final ConnectivityService connectivityService;

  /// Constructs a [TaskRepository].
  TaskRepository({
    required this.apiClient,
    required this.db,
    required this.connectivityService,
  });

  /// Single Source of Truth: Emits real-time reactive updates of active tasks from Drift SQLite.
  Stream<List<TaskModel>> watchTasks(String userId) {
    return db.watchActiveTasks(userId).map(
          (entries) => entries.map((e) => e.toModel()).toList(),
        );
  }

  /// Fetches an immediate snapshot of active local tasks from Drift SQLite.
  Future<List<TaskModel>> getLocalTasks(String userId) async {
    final entries = await db.getActiveTasks(userId);
    return entries.map((e) => e.toModel()).toList();
  }

  /// Offline-First task creation.
  ///
  /// Optimistically writes into Drift SQLite with [SyncStatus.pendingCreate] (or [SyncStatus.synced]
  /// if online), followed by immediate remote API sync if connectivity is present.
  Future<TaskModel> executeCreateTask({
    required String userId,
    required String title,
    String? description,
    TaskPriority priority = TaskPriority.medium,
    TaskCategory category = TaskCategory.work,
    DateTime? dueDate,
  }) async {
    final now = DateTime.now();
    final isOnline = await connectivityService.checkConnection();

    // 1. Optimistic write into Drift local database immediately
    final localId = await db.executeCreateTask(
      TasksTableCompanion.insert(
        userId: userId,
        title: title,
        description: drift.Value(description),
        isCompleted: const drift.Value(false),
        dueDate: drift.Value(dueDate),
        priority: drift.Value(priority.value),
        category: drift.Value(category.value),
        createdAt: now,
        updatedAt: now,
        syncStatus: drift.Value(isOnline ? SyncStatus.synced : SyncStatus.pendingCreate),
      ),
    );

    var createdModel = TaskModel(
      id: localId,
      localId: localId,
      userId: userId,
      title: title,
      description: description,
      isCompleted: false,
      dueDate: dueDate,
      priority: priority,
      category: category,
      createdAt: now,
      updatedAt: now,
      isPendingSync: !isOnline,
      syncStatus: isOnline ? SyncStatus.synced : SyncStatus.pendingCreate,
    );

    // 2. If online, sync to backend immediately
    if (isOnline) {
      try {
        final response = await apiClient.dio.post(
          '/tasks/',
          queryParameters: {'user_id': userId},
          data: createdModel.toApiCreateJson(),
        );

        final rawData = response.data['data'] as Map<String, dynamic>;
        final serverId = rawData['id'] as int;
        final serverUpdatedAt = DateTime.tryParse(rawData['updated_at']?.toString() ?? '') ?? now;

        await db.markTaskSynced(
          localId: localId,
          serverId: serverId,
          updatedAt: serverUpdatedAt,
        );

        createdModel = createdModel.copyWith(
          id: serverId,
          isPendingSync: false,
          syncStatus: SyncStatus.synced,
          lastSyncedAt: DateTime.now(),
        );
      } catch (e) {
        dev.log('Create API failed; marked as pending sync in Drift: $e', name: 'TaskRepo');
        final entry = (await db.getActiveTasks(userId)).firstWhere((e) => e.id == localId);
        await db.executeUpdateTask(entry.copyWith(syncStatus: SyncStatus.pendingCreate));
      }
    }

    return createdModel;
  }

  /// Offline-First task update.
  ///
  /// Updates local Drift SQLite record and attempts immediate API sync if connected.
  Future<void> executeUpdateTask({
    required String userId,
    required TaskModel task,
  }) async {
    final entry = await _findEntry(task);
    if (entry == null) return;

    final isOnline = await connectivityService.checkConnection();

    // 1. Update Drift SQLite locally
    await db.executeUpdateTask(
      entry.copyWith(
        title: task.title,
        description: drift.Value(task.description),
        isCompleted: task.isCompleted,
        dueDate: drift.Value(task.dueDate),
        priority: task.priority.value,
        category: task.category.value,
        updatedAt: DateTime.now(),
      ),
    );

    // 2. If online and task exists on server, push update
    if (isOnline && entry.serverId != null) {
      try {
        final response = await apiClient.dio.put(
          '/tasks/${entry.serverId}',
          queryParameters: {'user_id': userId},
          data: task.toApiCreateJson(),
        );

        final rawData = response.data['data'] as Map<String, dynamic>;
        final serverUpdatedAt =
            DateTime.tryParse(rawData['updated_at']?.toString() ?? '') ?? DateTime.now();

        await db.markTaskSynced(
          localId: entry.id,
          serverId: entry.serverId!,
          updatedAt: serverUpdatedAt,
        );
      } catch (e) {
        dev.log('Update API failed; preserved in Drift queue: $e', name: 'TaskRepo');
      }
    }
  }

  /// Offline-First task completion toggle.
  ///
  /// Instantly flips local completion boolean and dispatches update to server if online.
  Future<void> executeToggleCompletion({
    required String userId,
    required TaskModel task,
  }) async {
    final entry = await _findEntry(task);
    if (entry == null) return;

    final isOnline = await connectivityService.checkConnection();

    // 1. Toggle locally in Drift database
    await db.executeToggleCompletion(entry);

    // 2. Push to backend if online
    if (isOnline && entry.serverId != null) {
      try {
        final updatedModel = task.copyWith(isCompleted: !entry.isCompleted);
        await apiClient.dio.put(
          '/tasks/${entry.serverId}',
          queryParameters: {'user_id': userId},
          data: updatedModel.toApiCreateJson(),
        );

        await db.markTaskSynced(
          localId: entry.id,
          serverId: entry.serverId!,
          updatedAt: DateTime.now(),
        );
      } catch (e) {
        dev.log('Toggle completion API failed; queued in Drift: $e', name: 'TaskRepo');
      }
    }
  }

  /// Offline-First task deletion.
  ///
  /// Marks record as [SyncStatus.pendingDelete] in local database until remote API call completes.
  Future<void> executeDeleteTask({
    required String userId,
    required TaskModel task,
  }) async {
    final entry = await _findEntry(task);
    if (entry == null) return;

    final isOnline = await connectivityService.checkConnection();

    // 1. Soft-delete / queue locally in Drift
    await db.executeDeleteTask(entry);

    // 2. Push delete if online and registered on server
    if (isOnline && entry.serverId != null) {
      try {
        await apiClient.dio.delete(
          '/tasks/${entry.serverId}',
          queryParameters: {'user_id': userId},
        );
        await db.removePermanently(entry.id);
      } catch (e) {
        dev.log('Delete API failed; marked as pending delete in Drift: $e', name: 'TaskRepo');
      }
    }
  }

  /// Bidirectional Push & Pull synchronization engine.
  ///
  /// Step 1: Pushes all local uncommitted mutations (pending creations, updates, deletes) to FastAPI.
  /// Step 2: Pulls the latest tasks from FastAPI and upserts into Drift SQLite.
  Future<int> synchronize({
    required String userId,
    int skip = 0,
    int limit = AppConstants.defaultPageLimit,
  }) async {
    final isOnline = await connectivityService.checkConnection();
    if (!isOnline) {
      final local = await getLocalTasks(userId);
      return local.length;
    }

    dev.log('Starting offline-first synchronization engine...', name: 'SyncEngine');

    // === STEP 1: PUSH pending local mutations ===
    final pendingEntries = await db.getPendingSyncTasks(userId);
    for (final entry in pendingEntries) {
      try {
        if (entry.syncStatus == SyncStatus.pendingCreate) {
          final model = entry.toModel();
          final response = await apiClient.dio.post(
            '/tasks/',
            queryParameters: {'user_id': userId},
            data: model.toApiCreateJson(),
          );
          final rawData = response.data['data'] as Map<String, dynamic>;
          final serverId = rawData['id'] as int;
          final serverUpdatedAt =
              DateTime.tryParse(rawData['updated_at']?.toString() ?? '') ?? DateTime.now();

          await db.markTaskSynced(
            localId: entry.id,
            serverId: serverId,
            updatedAt: serverUpdatedAt,
          );
        } else if (entry.syncStatus == SyncStatus.pendingUpdate && entry.serverId != null) {
          final model = entry.toModel();
          final response = await apiClient.dio.put(
            '/tasks/${entry.serverId}',
            queryParameters: {'user_id': userId},
            data: model.toApiCreateJson(),
          );
          final rawData = response.data['data'] as Map<String, dynamic>;
          final serverUpdatedAt =
              DateTime.tryParse(rawData['updated_at']?.toString() ?? '') ?? DateTime.now();

          await db.markTaskSynced(
            localId: entry.id,
            serverId: entry.serverId!,
            updatedAt: serverUpdatedAt,
          );
        } else if (entry.syncStatus == SyncStatus.pendingDelete && entry.serverId != null) {
          await apiClient.dio.delete(
            '/tasks/${entry.serverId}',
            queryParameters: {'user_id': userId},
          );
          await db.removePermanently(entry.id);
        }
      } catch (e) {
        dev.log('Sync push error on entry ${entry.id}: $e', name: 'SyncEngine');
      }
    }

    // === STEP 2: PULL remote tasks from FastAPI ===
    int totalCount = 0;
    try {
      final response = await apiClient.dio.get(
        '/tasks/',
        queryParameters: {
          'user_id': userId,
          'skip': skip,
          'limit': limit,
        },
      );

      final data = response.data;
      final rawList = (data['data'] as List? ?? []);
      totalCount = (data['total'] as int?) ?? rawList.length;

      for (final raw in rawList) {
        final item = Map<String, dynamic>.from(raw as Map);
        final serverId = item['id'] as int;
        final title = item['title']?.toString() ?? '';
        final description = item['description']?.toString();
        final isCompleted = item['is_completed'] == true;
        final dueDate =
            item['due_date'] != null ? DateTime.tryParse(item['due_date'].toString()) : null;
        final priority = item['priority']?.toString() ?? 'Medium';
        final category = item['category']?.toString() ?? 'Work';
        final createdAt = item['created_at'] != null
            ? DateTime.tryParse(item['created_at'].toString()) ?? DateTime.now()
            : DateTime.now();
        final updatedAt = item['updated_at'] != null
            ? DateTime.tryParse(item['updated_at'].toString()) ?? DateTime.now()
            : DateTime.now();

        await db.upsertServerTask(
          serverId: serverId,
          userId: userId,
          title: title,
          description: description,
          isCompleted: isCompleted,
          dueDate: dueDate,
          priority: priority,
          category: category,
          createdAt: createdAt,
          updatedAt: updatedAt,
        );
      }
    } catch (e) {
      dev.log('Sync pull error: $e', name: 'SyncEngine');
    }

    final activeLocal = await getLocalTasks(userId);
    return totalCount > 0 ? totalCount : activeLocal.length;
  }

  Future<TaskEntry?> _findEntry(TaskModel task) async {
    if (task.localId != null) {
      final entries =
          await (db.select(db.tasksTable)..where((tbl) => tbl.id.equals(task.localId!))).get();
      if (entries.isNotEmpty) return entries.first;
    }
    if (task.id > 0) {
      final entries =
          await (db.select(db.tasksTable)..where((tbl) => tbl.serverId.equals(task.id))).get();
      if (entries.isNotEmpty) return entries.first;
    }
    return null;
  }
}

/// Riverpod provider for [TaskRepository].
final taskRepositoryProvider = Provider<TaskRepository>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  final db = ref.watch(appDatabaseProvider);
  final connectivity = ref.watch(connectivityServiceProvider);

  return TaskRepository(
    apiClient: apiClient,
    db: db,
    connectivityService: connectivity,
  );
});
