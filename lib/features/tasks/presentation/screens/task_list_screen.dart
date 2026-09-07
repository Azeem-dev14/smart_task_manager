import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smart_task_manager/core/theme/text_styles.dart';
import 'package:smart_task_manager/core/widgets/empty_state_view.dart';
import 'package:smart_task_manager/core/widgets/error_view.dart';
import 'package:smart_task_manager/core/widgets/offline_banner.dart';
import 'package:smart_task_manager/features/auth/data/auth_repository.dart';
import 'package:smart_task_manager/features/profile/presentation/screens/profile_screen.dart';
import 'package:smart_task_manager/features/tasks/domain/models/task_filter.dart';
import 'package:smart_task_manager/features/tasks/domain/models/task_model.dart';
import 'package:smart_task_manager/features/tasks/domain/models/task_sort_by.dart';
import 'package:smart_task_manager/features/tasks/presentation/controllers/task_list_notifier.dart';
import 'package:smart_task_manager/features/tasks/presentation/states/task_list_state.dart';
import 'package:smart_task_manager/features/tasks/presentation/widgets/task_card.dart';
import 'package:smart_task_manager/features/tasks/presentation/screens/task_form_screen.dart';
import 'package:smart_task_manager/features/tasks/presentation/screens/task_search_delegate.dart';

/// Primary dashboard screen displaying the task list with debounced search,
/// status filtering, sorting, pull-to-refresh, and infinite scroll pagination.
///
/// Only [currentUserProvider] is watched here, so the app bar and floating
/// action button are unaffected by the far more frequent [TaskListState]
/// updates (a background sync tick, a page loading, a filter change) — those
/// are scoped entirely to [_TaskListBody] below.
class TaskListScreen extends ConsumerWidget {
  /// Constructs a [TaskListScreen].
  const TaskListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final user = ref.watch(currentUserProvider);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Smart Task Manager',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            if (user != null && user.name.isNotEmpty)
              Text(
                'Hello, ${user.name}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'My profile',
            icon: const Icon(Icons.account_circle_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ProfileScreen()),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: const _TaskListBody(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => TaskFormScreen.show(context),
        icon: const Icon(Icons.add),
        label: const Text('New Task'),
      ),
    );
  }
}

/// The task-state-dependent portion of the dashboard: offline banner, search
/// bar, sort/filter row, task count, and the list itself.
class _TaskListBody extends ConsumerStatefulWidget {
  const _TaskListBody();

  @override
  ConsumerState<_TaskListBody> createState() => _TaskListBodyState();
}

class _TaskListBodyState extends ConsumerState<_TaskListBody> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  /// Infinite scroll: request the next page once the viewport nears the bottom.
  void _onScroll() {
    if (!_scrollController.hasClients) return;

    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 200) {
      ref.read(taskListControllerProvider.notifier).loadMoreTasks();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(taskListControllerProvider);
    final theme = Theme.of(context);
    final visibleTasks = state.visibleTasks;

    // Sync problems that happen while tasks are already on screen are reported
    // without taking the list away from the user.
    ref.listen<TaskListState>(taskListControllerProvider, (previous, next) {
      final error = next.error;
      if (error == null || error == previous?.error) return;
      if (next.allTasks.isEmpty) return;

      ErrorView.showSnackBar(context, error);
      ref.read(taskListControllerProvider.notifier).clearError();
    });

    return Column(
      children: [
        const OfflineBanner(),

        // Search bar — tapping opens the dedicated search page (SearchDelegate).
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Material(
            color: theme.inputDecorationTheme.fillColor,
            borderRadius: BorderRadius.circular(24),
            child: InkWell(
              borderRadius: BorderRadius.circular(24),
              onTap: () => showSearch(context: context, delegate: TaskSearchDelegate()),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(
                  children: [
                    Icon(
                      Icons.search,
                      size: 20,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Search tasks by title...',
                      style: context.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),

        // Sort menu and status filter chips.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                PopupMenuButton<TaskSortBy>(
                  tooltip: 'Sort tasks',
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  onSelected: ref.read(taskListControllerProvider.notifier).setSortBy,
                  itemBuilder: (_) => [
                    _sortMenuItem(context, TaskSortBy.createdDate, 'Sort by created date', state.sortBy),
                    _sortMenuItem(context, TaskSortBy.dueDate, 'Sort by due date', state.sortBy),
                    _sortMenuItem(context, TaskSortBy.priority, 'Sort by priority', state.sortBy),
                  ],
                  child: Chip(
                    avatar: const Icon(Icons.sort_rounded, size: 18),
                    label: const Text('Sort'),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  ),
                ),
                const SizedBox(width: 8),
                _filterChip('All', TaskFilter.all, state.filter),
                const SizedBox(width: 8),
                _filterChip('Pending', TaskFilter.pending, state.filter),
                const SizedBox(width: 8),
                _filterChip('Completed', TaskFilter.completed, state.filter),
              ],
            ),
          ),
        ),

        const Divider(height: 12),

        // Task count for the currently visible (filtered/searched) list.
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Tasks - ${visibleTasks.length}',
              style: context.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ),
        ),

        Expanded(child: _buildListArea(state, visibleTasks)),
      ],
    );
  }

  Widget _buildListArea(TaskListState state, List<TaskModel> visibleTasks) {
    if (state.isLoading && state.allTasks.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    // A failure with nothing cached to fall back on gets the full-screen
    // treatment, tailored to the type of error.
    if (state.error != null && state.allTasks.isEmpty) {
      return ErrorView(
        error: state.error!,
        onRetry: () => ref.read(taskListControllerProvider.notifier).refresh(showSyncing: true),
      );
    }

    if (visibleTasks.isEmpty) return _buildEmptyState(state);

    return RefreshIndicator(
      onRefresh: () => ref.read(taskListControllerProvider.notifier).refresh(),
      child: ListView.builder(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(top: 4, bottom: 88),
        itemCount: visibleTasks.length + (state.isLoadingMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= visibleTasks.length) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          return TaskCard(task: visibleTasks[index]);
        },
      ),
    );
  }

  Widget _buildEmptyState(TaskListState state) {
    if (state.searchQuery.trim().isNotEmpty) {
      return EmptyStateView(
        icon: Icons.search_off_rounded,
        title: 'No results found',
        description: 'No tasks match "${state.searchQuery}".',
      );
    }

    if (state.filter == TaskFilter.completed) {
      return const EmptyStateView(
        icon: Icons.check_circle_outline,
        title: 'No completed tasks',
        description: 'Mark tasks as done to see them here.',
      );
    }

    if (state.filter == TaskFilter.pending) {
      return const EmptyStateView(
        icon: Icons.done_all_rounded,
        title: 'Nothing pending',
        description: 'Every task is complete. Enjoy the clear list.',
      );
    }

    return const EmptyStateView(
      icon: Icons.task_alt_outlined,
      title: 'No tasks yet',
      description: 'Stay organized by adding your first task.',
    );
  }

  PopupMenuItem<TaskSortBy> _sortMenuItem(
    BuildContext context,
    TaskSortBy value,
    String label,
    TaskSortBy current,
  ) {
    final isSelected = current == value;

    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          Icon(
            isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
            size: 18,
            color: isSelected ? Theme.of(context).colorScheme.primary : null,
          ),
          const SizedBox(width: 8),
          Text(label),
        ],
      ),
    );
  }

  Widget _filterChip(String label, TaskFilter filter, TaskFilter current) {
    return FilterChip(
      label: Text(label),
      selected: current == filter,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      onSelected: (_) => ref.read(taskListControllerProvider.notifier).setFilter(filter),
    );
  }
}
