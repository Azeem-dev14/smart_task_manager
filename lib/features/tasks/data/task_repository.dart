import 'dart:developer' as dev;

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' as drift;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smart_task_manager/core/constants/app_constants.dart';
import 'package:smart_task_manager/core/database/app_database.dart';
import 'package:smart_task_manager/core/errors/app_exceptions.dart';
import 'package:smart_task_manager/core/network/api_client.dart';
import 'package:smart_task_manager/core/network/connectivity_service.dart';
import 'package:smart_task_manager/features/tasks/domain/models/task_model.dart';

/// Outcome of pulling one or more pages of tasks from the backend.
class TaskPageResult {
  /// Number of task records returned by the backend.
  final int fetched;

  /// Total number of tasks the backend holds for this user.
  final int total;

  /// Server identifiers contained in the fetched range.
  final Set<int> serverIds;

  /// Creates a [TaskPageResult].
  const TaskPageResult({
    required this.fetched,
    required this.total,
    this.serverIds = const {},
  });
}

/// Repository managing task persistence, reactive streams, optimistic local mutations,
/// and bidirectional synchronization between Drift SQLite and the remote FastAPI backend.
///
/// Every mutation is written to SQLite first and tagged with a [SyncStatus], so the
/// UI updates instantly and the change survives being made while offline. Remote
/// calls then reconcile the record. Failures are translated into the [AppException]
/// hierarchy so the presentation layer can react to the *kind* of failure.
class TaskRepository {
  /// REST API client for backend communication.
  final ApiClient apiClient;

  /// Local Drift SQLite database engine (Single Source of Truth).
  final AppDatabase db;

  /// Network connectivity service for real-time online status checks.
  final ConnectivityService connectivityService;

  /// Safety valve so a misbehaving backend can never spin the refresh loop forever.
  static const int _maxPagesPerRefresh = 50;

  /// Constructs a [TaskRepository].
  TaskRepository({
    required this.apiClient,
    required this.db,
    required this.connectivityService,
  });

  /// Single Source of Truth: emits real-time updates of active tasks from Drift SQLite.
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

  // ---------------------------------------------------------------------------
  // Mutations (offline-first, optimistic)
  // ---------------------------------------------------------------------------

  /// Creates a task locally, then pushes it to the backend when connected.
  ///
  /// The row is inserted as [SyncStatus.pendingCreate] and only promoted to
  /// synced once the backend has acknowledged it, so a failed request can never
  /// leave behind a row that claims to exist remotely.
  Future<void> createTask({
    required String userId,
    required String title,
    String? description,
    TaskPriority priority = TaskPriority.medium,
    TaskCategory category = TaskCategory.work,
    DateTime? dueDate,
  }) async {
    final now = DateTime.now();

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
        syncStatus: const drift.Value(SyncStatus.pendingCreate),
      ),
    );

    if (!await connectivityService.checkConnection()) return;

    final entry = await db.findByLocalId(localId);
    if (entry == null) return;

    await _guardRemoteMutation(() => _pushCreate(userId, entry));
  }

  /// Updates a task locally, then pushes the change to the backend when connected.
  Future<void> updateTask({
    required String userId,
    required TaskModel task,
  }) async {
    final entry = await _findEntry(task);
    if (entry == null) {
      throw const CacheException('That task no longer exists.', code: 'task-missing');
    }

    await db.executeUpdateTask(
      entry.copyWith(
        title: task.title,
        description: drift.Value(task.description),
        isCompleted: task.isCompleted,
        dueDate: drift.Value(task.dueDate),
        priority: task.priority.value,
        category: task.category.value,
      ),
    );

    if (!await connectivityService.checkConnection()) return;

    final updated = await db.findByLocalId(entry.id);
    if (updated == null) return;

    await _guardRemoteMutation(() => _pushUpdate(userId, updated));
  }

  /// Flips a task's completion flag locally and mirrors it to the backend.
  Future<void> toggleCompletion({
    required String userId,
    required TaskModel task,
  }) async {
    final entry = await _findEntry(task);
    if (entry == null) {
      throw const CacheException('That task no longer exists.', code: 'task-missing');
    }

    await db.executeToggleCompletion(entry);

    if (!await connectivityService.checkConnection()) return;

    final updated = await db.findByLocalId(entry.id);
    if (updated == null) return;

    await _guardRemoteMutation(() => _pushUpdate(userId, updated));
  }

  /// Deletes a task locally, then confirms the deletion with the backend.
  ///
  /// Tasks that never reached the server are removed outright; the rest are kept
  /// as [SyncStatus.pendingDelete] tombstones until the backend confirms.
  Future<void> deleteTask({
    required String userId,
    required TaskModel task,
  }) async {
    final entry = await _findEntry(task);
    if (entry == null) return;

    await db.executeDeleteTask(entry);

    if (entry.serverId == null || entry.syncStatus == SyncStatus.pendingCreate) return;
    if (!await connectivityService.checkConnection()) return;

    await _guardRemoteMutation(() => _pushDelete(userId, entry));
  }

  // ---------------------------------------------------------------------------
  // Synchronization
  // ---------------------------------------------------------------------------

  /// Pushes every locally queued mutation for [userId] to the backend.
  ///
  /// Never throws: anything still failing stays queued and keeps its "pending
  /// sync" badge in the UI, ready for the next reconnect.
  Future<void> pushPendingChanges(String userId) async {
    final pending = await db.getPendingSyncTasks(userId);

    for (final entry in pending) {
      try {
        switch (entry.syncStatus) {
          case SyncStatus.pendingCreate:
            await _pushCreate(userId, entry);
          case SyncStatus.pendingUpdate:
            if (entry.serverId != null) await _pushUpdate(userId, entry);
          case SyncStatus.pendingDelete:
            if (entry.serverId != null) await _pushDelete(userId, entry);
        }
      } catch (e) {
        dev.log('Sync push failed for local task ${entry.id}: $e', name: 'SyncEngine');
      }
    }
  }

  /// Pulls a single page of tasks and upserts them into the local database.
  ///
  /// Throws a typed [AppException] when the request fails.
  Future<TaskPageResult> pullPage({
    required String userId,
    required int skip,
    int limit = AppConstants.defaultPageLimit,
  }) async {
    try {
      final response = await apiClient.dio.get<dynamic>(
        '/tasks/',
        queryParameters: {'user_id': userId, 'skip': skip, 'limit': limit},
      );

      final body = response.data;
      if (body is! Map) {
        throw const ServerException(
          'Received an unexpected response from the server.',
          code: 'malformed-payload',
        );
      }

      final rawList = (body['data'] as List?) ?? const [];
      final serverIds = <int>{};

      for (final raw in rawList) {
        if (raw is! Map) continue;
        final task = TaskModel.fromJson(Map<String, dynamic>.from(raw));
        serverIds.add(task.id);

        await db.upsertServerTask(
          serverId: task.id,
          userId: userId,
          title: task.title,
          description: task.description,
          isCompleted: task.isCompleted,
          dueDate: task.dueDate,
          priority: task.priority.value,
          category: task.category.value,
          createdAt: task.createdAt,
          updatedAt: task.updatedAt,
        );
      }

      return TaskPageResult(
        fetched: rawList.length,
        total: (body['total'] as int?) ?? (skip + rawList.length),
        serverIds: serverIds,
      );
    } on DioException catch (e) {
      throw ApiClient.toAppException(e);
    }
  }

  /// Performs a full refresh: pushes queued work, then re-pulls from the first page.
  ///
  /// Pages are pulled until at least [minimumItems] records have been refreshed
  /// (so everything the user already scrolled past stays current) or the backend
  /// runs out of tasks. When the complete list was retrieved, rows deleted on
  /// another device are pruned locally.
  ///
  /// Throws a typed [AppException] when the pull fails.
  Future<TaskPageResult> refreshTasks({
    required String userId,
    int minimumItems = AppConstants.defaultPageLimit,
    int limit = AppConstants.defaultPageLimit,
  }) async {
    await pushPendingChanges(userId);

    final serverIds = <int>{};
    var loaded = 0;
    var total = 0;

    for (var page = 0; page < _maxPagesPerRefresh; page++) {
      final result = await pullPage(userId: userId, skip: loaded, limit: limit);

      serverIds.addAll(result.serverIds);
      loaded += result.fetched;
      total = result.total;

      final reachedEnd = result.fetched < limit || loaded >= total;
      if (reachedEnd || loaded >= minimumItems) break;
    }

    if (loaded >= total) {
      await db.pruneSyncedTasksMissingFrom(userId, serverIds);
    }

    return TaskPageResult(fetched: loaded, total: total, serverIds: serverIds);
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  /// Runs a remote mutation that has already been committed locally.
  ///
  /// A network failure is expected offline-first behaviour: the record simply
  /// stays queued. A server rejection is not — it means the backend refused the
  /// change, so it is surfaced to the caller.
  Future<void> _guardRemoteMutation(Future<void> Function() action) async {
    try {
      await action();
    } on NetworkException catch (e) {
      dev.log('Deferred to sync queue: ${e.message}', name: 'TaskRepo');
    }
  }

  Future<void> _pushCreate(String userId, TaskEntry entry) async {
    try {
      final response = await apiClient.dio.post<dynamic>(
        '/tasks/',
        queryParameters: {'user_id': userId},
        data: entry.toModel().toApiCreateJson(),
      );

      final data = _dataObject(response.data);
      await db.markTaskSynced(
        localId: entry.id,
        serverId: data['id'] as int,
        updatedAt: _parseDate(data['updated_at']) ?? DateTime.now(),
      );
    } on DioException catch (e) {
      throw ApiClient.toAppException(e);
    }
  }

  Future<void> _pushUpdate(String userId, TaskEntry entry) async {
    if (entry.serverId == null) return;

    try {
      final response = await apiClient.dio.put<dynamic>(
        '/tasks/${entry.serverId}',
        queryParameters: {'user_id': userId},
        data: entry.toModel().toApiCreateJson(),
      );

      final data = _dataObject(response.data);
      await db.markTaskSynced(
        localId: entry.id,
        serverId: entry.serverId!,
        updatedAt: _parseDate(data['updated_at']) ?? DateTime.now(),
      );
    } on DioException catch (e) {
      final mapped = ApiClient.toAppException(e);
      // The task is already gone remotely, so the local copy is the stale one.
      if (mapped is ServerException && mapped.statusCode == 404) {
        await db.removePermanently(entry.id);
        return;
      }
      throw mapped;
    }
  }

  Future<void> _pushDelete(String userId, TaskEntry entry) async {
    try {
      await apiClient.dio.delete<dynamic>(
        '/tasks/${entry.serverId}',
        queryParameters: {'user_id': userId},
      );
      await db.removePermanently(entry.id);
    } on DioException catch (e) {
      final mapped = ApiClient.toAppException(e);
      // Already deleted remotely: the tombstone has served its purpose.
      if (mapped is ServerException && mapped.statusCode == 404) {
        await db.removePermanently(entry.id);
        return;
      }
      throw mapped;
    }
  }

  /// Extracts the `data` object from the backend's `ResponseModel` envelope.
  Map<String, dynamic> _dataObject(dynamic body) {
    if (body is Map && body['data'] is Map) {
      return Map<String, dynamic>.from(body['data'] as Map);
    }
    throw const ServerException(
      'Received an unexpected response from the server.',
      code: 'malformed-payload',
    );
  }

  DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }

  Future<TaskEntry?> _findEntry(TaskModel task) async {
    if (task.localId != null) {
      final byLocalId = await db.findByLocalId(task.localId!);
      if (byLocalId != null) return byLocalId;
    }
    if (task.id > 0) {
      return db.findByServerId(task.id);
    }
    return null;
  }
}

/// Riverpod provider for [TaskRepository].
final taskRepositoryProvider = Provider<TaskRepository>((ref) {
  return TaskRepository(
    apiClient: ref.watch(apiClientProvider),
    db: ref.watch(appDatabaseProvider),
    connectivityService: ref.watch(connectivityServiceProvider),
  );
});
