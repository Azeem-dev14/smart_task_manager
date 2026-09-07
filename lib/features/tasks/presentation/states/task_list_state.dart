import 'package:smart_task_manager/features/tasks/domain/models/task_filter.dart';
import 'package:smart_task_manager/features/tasks/domain/models/task_model.dart';
import 'package:smart_task_manager/features/tasks/domain/models/task_sort_by.dart';

/// Immutable state representation of the Task List presentation screen.
///
/// Holds the active list of tasks, loading/syncing flags, client-side filters,
/// search queries, and pagination metadata.
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

  /// User-friendly error message if a critical failure occurs, or `null`.
  final String? errorMessage;

  /// Selected completion filter ([TaskFilter.all], [TaskFilter.pending], [TaskFilter.completed]).
  final TaskFilter filter;

  /// Active sorting criterion ([TaskSortBy.createdDate], [TaskSortBy.dueDate], [TaskSortBy.priority]).
  final TaskSortBy sortBy;

  /// Real-time search query string (debounced by 300ms in notifier).
  final String searchQuery;

  /// Total count of tasks available remotely as reported by the backend.
  final int totalCount;

  /// Constructs an immutable [TaskListState].
  const TaskListState({
    this.allTasks = const [],
    this.isLoading = false,
    this.isSyncing = false,
    this.isLoadingMore = false,
    this.hasMore = true,
    this.errorMessage,
    this.filter = TaskFilter.all,
    this.sortBy = TaskSortBy.createdDate,
    this.searchQuery = '',
    this.totalCount = 0,
  });

  /// Creates a copy of this state with specified parameters overridden.
  TaskListState copyWith({
    List<TaskModel>? allTasks,
    bool? isLoading,
    bool? isSyncing,
    bool? isLoadingMore,
    bool? hasMore,
    String? errorMessage,
    TaskFilter? filter,
    TaskSortBy? sortBy,
    String? searchQuery,
    int? totalCount,
  }) {
    return TaskListState(
      allTasks: allTasks ?? this.allTasks,
      isLoading: isLoading ?? this.isLoading,
      isSyncing: isSyncing ?? this.isSyncing,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
      errorMessage: errorMessage,
      filter: filter ?? this.filter,
      sortBy: sortBy ?? this.sortBy,
      searchQuery: searchQuery ?? this.searchQuery,
      totalCount: totalCount ?? this.totalCount,
    );
  }

  /// Derived computed list of tasks after applying active [filter], [searchQuery], and [sortBy].
  List<TaskModel> get visibleTasks {
    List<TaskModel> list = List.of(allTasks);

    // 1. Apply status filter
    switch (filter) {
      case TaskFilter.completed:
        list = list.where((t) => t.isCompleted).toList();
        break;
      case TaskFilter.pending:
        list = list.where((t) => !t.isCompleted).toList();
        break;
      case TaskFilter.all:
        break;
    }

    // 2. Apply search filter by title (case-insensitive)
    if (searchQuery.trim().isNotEmpty) {
      final query = searchQuery.toLowerCase().trim();
      list = list.where((t) => t.title.toLowerCase().contains(query)).toList();
    }

    // 3. Apply active sorting
    switch (sortBy) {
      case TaskSortBy.createdDate:
        list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        break;
      case TaskSortBy.dueDate:
        list.sort((a, b) {
          if (a.dueDate == null && b.dueDate == null) return 0;
          if (a.dueDate == null) return 1;
          if (b.dueDate == null) return -1;
          return a.dueDate!.compareTo(b.dueDate!);
        });
        break;
      case TaskSortBy.priority:
        final order = {TaskPriority.high: 0, TaskPriority.medium: 1, TaskPriority.low: 2};
        list.sort((a, b) => (order[a.priority] ?? 1).compareTo(order[b.priority] ?? 1));
        break;
    }

    return list;
  }
}
