import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smart_task_manager/core/constants/app_constants.dart';
import 'package:smart_task_manager/core/network/connectivity_service.dart';
import 'package:smart_task_manager/features/auth/data/auth_repository.dart';
import 'package:smart_task_manager/features/tasks/data/task_repository.dart';
import 'package:smart_task_manager/features/tasks/domain/models/task_filter.dart';
import 'package:smart_task_manager/features/tasks/domain/models/task_model.dart';
import 'package:smart_task_manager/features/tasks/domain/models/task_sort_by.dart';
import 'package:smart_task_manager/features/tasks/presentation/states/task_list_state.dart';

/// Riverpod state notifier managing business logic, reactive Drift database subscriptions,
/// automatic network sync on reconnect, search debouncing, and CRUD mutations.
class TaskListNotifier extends Notifier<TaskListState> {
  Timer? _debounceTimer;
  StreamSubscription<List<TaskModel>>? _dbSubscription;

  @override
  TaskListState build() {
    // 1. Subscribe to Drift SQLite reactive task stream (Single Source of Truth)
    _listenToDatabase();

    // 2. React to network transitions: automatically synchronize upon reconnection
    ref.listen(isOnlineProvider, (previous, next) {
      final wasOnline = previous?.value ?? true;
      final isOnline = next.value ?? false;
      if (!wasOnline && isOnline) {
        synchronize();
      }
    });

    // 3. Clean up timers and database stream subscriptions on disposal
    ref.onDispose(() {
      _debounceTimer?.cancel();
      _dbSubscription?.cancel();
    });

    // 4. Trigger initial remote sync in background microtask
    Future.microtask(() => synchronize(showLoading: true));

    return const TaskListState(isLoading: true);
  }

  String get _currentUserId {
    final user = ref.read(currentUserProvider);
    return user?.uid ?? 'guest_user';
  }

  TaskRepository get _repository => ref.read(taskRepositoryProvider);

  /// Subscribes to Drift SQLite stream for real-time reactive UI updates
  void _listenToDatabase() {
    _dbSubscription?.cancel();
    _dbSubscription = _repository.watchTasks(_currentUserId).listen((tasks) {
      state = state.copyWith(
        allTasks: tasks,
        isLoading: false,
      );
    });
  }

  /// Runs bidirectional Push (pending local executions) & Pull (server tasks) synchronization.
  Future<void> synchronize({bool showLoading = false}) async {
    if (showLoading) {
      state = state.copyWith(isSyncing: true, errorMessage: null);
    }

    try {
      final total = await _repository.synchronize(
        userId: _currentUserId,
        skip: 0,
        limit: AppConstants.defaultPageLimit,
      );

      final hasMore = state.allTasks.length < total;
      state = state.copyWith(
        isSyncing: false,
        isLoading: false,
        totalCount: total,
        hasMore: hasMore,
      );
    } catch (e) {
      state = state.copyWith(
        isSyncing: false,
        isLoading: false,
        errorMessage: e.toString(),
      );
    }
  }

  /// Pull-to-refresh handler invoked by the UI.
  Future<void> refresh() => synchronize(showLoading: false);

  /// Loads the next page of tasks using `skip & limit` pagination.
  Future<void> loadMoreTasks() async {
    if (state.isLoading || state.isLoadingMore || !state.hasMore) return;

    state = state.copyWith(isLoadingMore: true);

    try {
      final skip = state.allTasks.length;
      final total = await _repository.synchronize(
        userId: _currentUserId,
        skip: skip,
        limit: AppConstants.defaultPageLimit,
      );

      final hasMore = state.allTasks.length < total;
      state = state.copyWith(
        isLoadingMore: false,
        totalCount: total,
        hasMore: hasMore,
      );
    } catch (e) {
      state = state.copyWith(isLoadingMore: false);
    }
  }

  /// Updates the active task completion filter.
  void setFilter(TaskFilter filter) {
    state = state.copyWith(filter: filter);
  }

  /// Updates the active task sorting criterion.
  void setSortBy(TaskSortBy sortBy) {
    state = state.copyWith(sortBy: sortBy);
  }

  /// Updates search query with 300ms debouncing to prevent excessive filtering recalculations.
  void setSearchQuery(String query) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      state = state.copyWith(searchQuery: query);
    });
  }

  /// Creates a new task with optimistic local SQLite write followed by background sync.
  Future<void> addTask({
    required String title,
    String? description,
    TaskPriority priority = TaskPriority.medium,
    TaskCategory category = TaskCategory.work,
    DateTime? dueDate,
  }) async {
    await _repository.executeCreateTask(
      userId: _currentUserId,
      title: title,
      description: description,
      priority: priority,
      category: category,
      dueDate: dueDate,
    );
  }

  /// Toggles task completion state with instant local response and background sync.
  Future<void> toggleTaskCompleted(TaskModel task) async {
    await _repository.executeToggleCompletion(
      userId: _currentUserId,
      task: task,
    );
  }

  /// Modifies an existing task's attributes in Drift SQLite and pushes to backend.
  Future<void> updateTaskDetails(TaskModel task) async {
    await _repository.executeUpdateTask(
      userId: _currentUserId,
      task: task,
    );
  }

  /// Deletes a task locally (or marks for delete) and syncs deletion with remote API.
  Future<void> deleteTask(TaskModel task) async {
    await _repository.executeDeleteTask(
      userId: _currentUserId,
      task: task,
    );
  }
}

/// Global Riverpod provider for the [TaskListNotifier].
final taskListControllerProvider = NotifierProvider<TaskListNotifier, TaskListState>(() {
  return TaskListNotifier();
});
