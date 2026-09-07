import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smart_task_manager/core/constants/app_constants.dart';
import 'package:smart_task_manager/core/errors/app_exceptions.dart';
import 'package:smart_task_manager/core/network/api_client.dart';
import 'package:smart_task_manager/core/network/connectivity_service.dart';
import 'package:smart_task_manager/features/auth/data/auth_repository.dart';
import 'package:smart_task_manager/features/tasks/data/task_repository.dart';
import 'package:smart_task_manager/features/tasks/domain/models/task_filter.dart';
import 'package:smart_task_manager/features/tasks/domain/models/task_model.dart';
import 'package:smart_task_manager/features/tasks/domain/models/task_sort_by.dart';
import 'package:smart_task_manager/features/tasks/presentation/states/task_list_state.dart';

/// Riverpod notifier owning all task list business logic: the reactive Drift
/// subscription, remote pagination, automatic sync on reconnect, debounced
/// search, and CRUD mutations.
///
/// The notifier is scoped to the signed-in user, so signing in as a different
/// account rebuilds it from scratch instead of inheriting the previous session's
/// tasks and pagination cursor.
class TaskListNotifier extends Notifier<TaskListState> {
  Timer? _debounceTimer;
  StreamSubscription<List<TaskModel>>? _dbSubscription;
  bool _disposed = false;

  @override
  TaskListState build() {
    final userId = ref.watch(currentUserProvider.select((user) => user?.uid));

    _disposed = false;
    ref.onDispose(() {
      _disposed = true;
      _debounceTimer?.cancel();
      _dbSubscription?.cancel();
    });

    // Signed out: nothing to observe and nothing to sync.
    if (userId == null || userId.isEmpty) return const TaskListState();

    _listenToDatabase(userId);

    // Re-run the sync engine when connectivity comes back, flushing everything
    // that was queued while the device was offline.
    ref.listen(isOnlineProvider, (previous, next) {
      final wasOnline = previous?.value ?? false;
      final isOnline = next.value ?? false;
      if (!wasOnline && isOnline) refresh();
    });

    Future.microtask(() => _runInitialSync(userId));

    return const TaskListState(isLoading: true);
  }

  TaskRepository get _repository => ref.read(taskRepositoryProvider);

  String? get _userId => ref.read(currentUserProvider)?.uid;

  /// Guards against a late async callback writing to a disposed notifier.
  void _setState(TaskListState Function(TaskListState current) update) {
    if (_disposed) return;
    state = update(state);
  }

  /// Subscribes to the Drift stream so local writes are reflected immediately.
  void _listenToDatabase(String userId) {
    _dbSubscription?.cancel();
    _dbSubscription = _repository.watchTasks(userId).listen(
      (tasks) => _setState((s) => s.copyWith(allTasks: tasks, isLoading: false)),
      onError: (Object e) => _setState(
        (s) => s.copyWith(
          isLoading: false,
          error: CacheException(
            'Could not read your saved tasks.',
            code: 'db-read-failed',
            originalError: e,
          ),
        ),
      ),
    );
  }

  Future<void> _runInitialSync(String userId) async {
    if (_disposed) return;

    // Local data renders first; a missing network simply leaves the cache in
    // place rather than surfacing an error the offline banner already explains.
    if (!await ref.read(connectivityServiceProvider).checkConnection()) {
      _setState((s) => s.copyWith(isLoading: false));
      return;
    }

    await refresh(showSyncing: true);
  }

  /// Pull-to-refresh and reconnect handler: pushes queued work, then re-pulls
  /// every page the user has already seen.
  Future<void> refresh({bool showSyncing = false}) async {
    final userId = _userId;
    if (userId == null || userId.isEmpty) return;

    _setState((s) => s.copyWith(isSyncing: showSyncing, clearError: true));

    try {
      // Re-pull at least everything the user has already scrolled through, so
      // a refresh never leaves stale rows behind the current scroll position.
      final coverage = state.loadedFromServer > AppConstants.defaultPageLimit
          ? state.loadedFromServer
          : AppConstants.defaultPageLimit;

      final result = await _repository.refreshTasks(userId: userId, minimumItems: coverage);

      _setState(
        (s) => s.copyWith(
          isSyncing: false,
          isLoading: false,
          totalCount: result.total,
          loadedFromServer: result.fetched,
          hasMore: result.fetched < result.total,
          clearError: true,
        ),
      );
    } catch (e) {
      _reportFailure(e);
    }
  }

  /// Loads the next page of tasks from the backend using `skip` and `limit`.
  Future<void> loadMoreTasks() async {
    if (state.isLoading || state.isLoadingMore || state.isSyncing || !state.hasMore) return;

    final userId = _userId;
    if (userId == null || userId.isEmpty) return;

    _setState((s) => s.copyWith(isLoadingMore: true));

    try {
      final result = await _repository.pullPage(
        userId: userId,
        skip: state.loadedFromServer,
        limit: AppConstants.defaultPageLimit,
      );

      final loaded = state.loadedFromServer + result.fetched;
      _setState(
        (s) => s.copyWith(
          isLoadingMore: false,
          totalCount: result.total,
          loadedFromServer: loaded,
          // A short page means the backend has nothing left to give.
          hasMore: result.fetched > 0 && loaded < result.total,
        ),
      );
    } catch (e) {
      _setState((s) => s.copyWith(isLoadingMore: false, error: ApiClient.toAppException(e)));
    }
  }

  void _reportFailure(Object error) {
    final mapped = ApiClient.toAppException(error);

    // Losing connectivity while cached tasks are on screen is normal
    // offline-first behaviour, and the offline banner already explains it.
    final suppress = mapped is NetworkException && state.allTasks.isNotEmpty;

    if (suppress) {
      _setState((s) => s.copyWith(isSyncing: false, isLoading: false, clearError: true));
      return;
    }

    _setState((s) => s.copyWith(isSyncing: false, isLoading: false, error: mapped));
  }

  /// Updates the active task completion filter.
  void setFilter(TaskFilter filter) => _setState((s) => s.copyWith(filter: filter));

  /// Updates the active task sorting criterion.
  void setSortBy(TaskSortBy sortBy) => _setState((s) => s.copyWith(sortBy: sortBy));

  /// Updates the search query, debounced by 300ms to avoid re-filtering per keystroke.
  void setSearchQuery(String query) {
    _debounceTimer?.cancel();

    if (query.isEmpty) {
      _setState((s) => s.copyWith(searchQuery: ''));
      return;
    }

    _debounceTimer = Timer(
      const Duration(milliseconds: 300),
      () => _setState((s) => s.copyWith(searchQuery: query)),
    );
  }

  /// Clears the currently displayed synchronization error.
  void clearError() => _setState((s) => s.copyWith(clearError: true));

  /// Creates a task with an optimistic local write followed by a background push.
  Future<void> addTask({
    required String title,
    String? description,
    TaskPriority priority = TaskPriority.medium,
    TaskCategory category = TaskCategory.work,
    DateTime? dueDate,
  }) {
    return _mutate(
      (userId) => _repository.createTask(
        userId: userId,
        title: title,
        description: description,
        priority: priority,
        category: category,
        dueDate: dueDate,
      ),
    );
  }

  /// Toggles a task's completion state locally, then syncs it.
  Future<void> toggleTaskCompleted(TaskModel task) {
    return _mutate((userId) => _repository.toggleCompletion(userId: userId, task: task));
  }

  /// Applies edits to an existing task and pushes them to the backend.
  Future<void> updateTaskDetails(TaskModel task) {
    return _mutate((userId) => _repository.updateTask(userId: userId, task: task));
  }

  /// Deletes a task locally and syncs the deletion.
  Future<void> deleteTask(TaskModel task) {
    return _mutate((userId) => _repository.deleteTask(userId: userId, task: task));
  }

  /// Runs a mutation for the signed-in user, surfacing failures through state.
  ///
  /// The local write has already been committed by the time anything can fail,
  /// so the UI stays responsive and the record simply keeps its pending badge.
  Future<void> _mutate(Future<void> Function(String userId) action) async {
    final userId = _userId;
    if (userId == null || userId.isEmpty) {
      _setState(
        (s) => s.copyWith(
          error: const AuthException('You need to be signed in to manage tasks.'),
        ),
      );
      return;
    }

    try {
      await action(userId);
    } catch (e) {
      _setState((s) => s.copyWith(error: ApiClient.toAppException(e)));
    }
  }
}

/// Global Riverpod provider for the [TaskListNotifier].
final taskListControllerProvider =
    NotifierProvider<TaskListNotifier, TaskListState>(TaskListNotifier.new);
