import 'package:smart_task_manager/core/errors/app_exceptions.dart';
import 'package:smart_task_manager/features/tasks/domain/models/task_filter.dart';
import 'package:smart_task_manager/features/tasks/domain/models/task_model.dart';
import 'package:smart_task_manager/features/tasks/domain/models/task_sort_by.dart';

/// Immutable state representation of the Task List presentation screen.
///
/// Holds the tasks cached locally, loading/syncing flags, the client-side
/// filter, search and sort selections, and the remote pagination cursor.
class TaskListState {
  /// Complete collection of tasks currently cached in the local Drift SQLite database.
  final List<TaskModel> allTasks;

  /// True during initial loading or full refresh.
  final bool isLoading;

  /// True when background network push/pull synchronization is underway.
  final bool isSyncing;

  /// True when fetching an additional page of tasks during infinite scrolling.
  final bool isLoadingMore;

  /// Whether additional tasks exist on the remote server to be fetched.
  final bool hasMore;

  /// Typed failure from the most recent synchronization, or `null`.
  ///
  /// Kept as an [AppException] rather than a string so the UI can render a
  /// different treatment per failure kind.
  final AppException? error;

  /// Selected completion filter ([TaskFilter.all], [TaskFilter.pending], [TaskFilter.completed]).
  final TaskFilter filter;

  /// Active sorting criterion ([TaskSortBy.createdDate], [TaskSortBy.dueDate], [TaskSortBy.priority]).
  final TaskSortBy sortBy;

  /// Real-time search query string (debounced by 300ms in the notifier).
  final String searchQuery;

  /// Total count of tasks available remotely as reported by the backend.
  final int totalCount;

  /// Number of records already pulled from the backend.
  ///
  /// This is the `skip` cursor for the next page. It deliberately tracks remote
  /// records only — counting local rows instead would double count tasks that
  /// were created offline and have not reached the server yet.
  final int loadedFromServer;

  /// Constructs an immutable [TaskListState].
  const TaskListState({
    this.allTasks = const [],
    this.isLoading = false,
    this.isSyncing = false,
    this.isLoadingMore = false,
    this.hasMore = false,
    this.error,
    this.filter = TaskFilter.all,
    this.sortBy = TaskSortBy.createdDate,
    this.searchQuery = '',
    this.totalCount = 0,
    this.loadedFromServer = 0,
  });

  /// Creates a copy of this state with the specified parameters overridden.
  ///
  /// [error] is only replaced when a value is supplied; pass `clearError` to
  /// drop a previous failure, so unrelated updates cannot silently discard it.
  TaskListState copyWith({
    List<TaskModel>? allTasks,
    bool? isLoading,
    bool? isSyncing,
    bool? isLoadingMore,
    bool? hasMore,
    AppException? error,
    bool clearError = false,
    TaskFilter? filter,
    TaskSortBy? sortBy,
    String? searchQuery,
    int? totalCount,
    int? loadedFromServer,
  }) {
    return TaskListState(
      allTasks: allTasks ?? this.allTasks,
      isLoading: isLoading ?? this.isLoading,
      isSyncing: isSyncing ?? this.isSyncing,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
      error: clearError ? null : (error ?? this.error),
      filter: filter ?? this.filter,
      sortBy: sortBy ?? this.sortBy,
      searchQuery: searchQuery ?? this.searchQuery,
      totalCount: totalCount ?? this.totalCount,
      loadedFromServer: loadedFromServer ?? this.loadedFromServer,
    );
  }

  /// Whether any client-side filter or search is narrowing the list.
  bool get hasActiveQuery => searchQuery.trim().isNotEmpty || filter != TaskFilter.all;

  /// Derived list of tasks after applying the active [filter], [searchQuery] and [sortBy].
  List<TaskModel> get visibleTasks {
    final list = <TaskModel>[];

    final query = searchQuery.trim().toLowerCase();
    for (final task in allTasks) {
      switch (filter) {
        case TaskFilter.completed:
          if (!task.isCompleted) continue;
        case TaskFilter.pending:
          if (task.isCompleted) continue;
        case TaskFilter.all:
          break;
      }

      if (query.isNotEmpty && !task.title.toLowerCase().contains(query)) continue;

      list.add(task);
    }

    switch (sortBy) {
      case TaskSortBy.createdDate:
        list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      case TaskSortBy.dueDate:
        // Tasks without a deadline sort last, in both directions.
        list.sort((a, b) {
          if (a.dueDate == null && b.dueDate == null) return 0;
          if (a.dueDate == null) return 1;
          if (b.dueDate == null) return -1;
          return a.dueDate!.compareTo(b.dueDate!);
        });
      case TaskSortBy.priority:
        list.sort((a, b) {
          final byPriority = a.priority.rank.compareTo(b.priority.rank);
          // Stable, predictable ordering inside a priority band.
          return byPriority != 0 ? byPriority : b.createdAt.compareTo(a.createdAt);
        });
    }

    return list;
  }
}
