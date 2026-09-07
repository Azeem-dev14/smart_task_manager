import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smart_task_manager/core/widgets/empty_state_view.dart';
import 'package:smart_task_manager/core/widgets/error_view.dart';
import 'package:smart_task_manager/core/widgets/offline_banner.dart';
import 'package:smart_task_manager/features/auth/data/auth_repository.dart';
import 'package:smart_task_manager/features/profile/presentation/controllers/theme_controller.dart';
import 'package:smart_task_manager/features/profile/presentation/screens/profile_screen.dart';
import 'package:smart_task_manager/features/tasks/domain/models/task_filter.dart';
import 'package:smart_task_manager/features/tasks/domain/models/task_model.dart';
import 'package:smart_task_manager/features/tasks/domain/models/task_sort_by.dart';
import 'package:smart_task_manager/features/tasks/presentation/controllers/task_list_notifier.dart';
import 'package:smart_task_manager/features/tasks/presentation/states/task_list_state.dart';
import 'package:smart_task_manager/features/tasks/presentation/widgets/task_card.dart';
import 'package:smart_task_manager/features/tasks/presentation/widgets/task_form_sheet.dart';

/// Primary dashboard screen displaying the task list with debounced search,
/// status filtering, sorting, pull-to-refresh, and infinite scroll pagination.
class TaskListScreen extends ConsumerStatefulWidget {
  /// Constructs a [TaskListScreen].
  const TaskListScreen({super.key});

  @override
  ConsumerState<TaskListScreen> createState() => _TaskListScreenState();
}

class _TaskListScreenState extends ConsumerState<TaskListScreen> {
  final _scrollController = ScrollController();
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _searchController.dispose();
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
    final isDark = theme.brightness == Brightness.dark;
    final user = ref.watch(currentUserProvider);
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

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Smart Task Manager',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            if (user != null && user.name.isNotEmpty)
              Text(
                'Hello, ${user.name}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: isDark ? 'Switch to light mode' : 'Switch to dark mode',
            icon: Icon(isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
            onPressed: () => ref.read(themeControllerProvider.notifier).toggleTheme(),
          ),
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
      body: Column(
        children: [
          const OfflineBanner(),

          // Search field and sort menu.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Row(
              children: [
                Expanded(
                  child: ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _searchController,
                    builder: (context, value, _) {
                      return TextField(
                        controller: _searchController,
                        textInputAction: TextInputAction.search,
                        onChanged: ref.read(taskListControllerProvider.notifier).setSearchQuery,
                        decoration: InputDecoration(
                          hintText: 'Search tasks by title...',
                          prefixIcon: const Icon(Icons.search, size: 20),
                          suffixIcon: value.text.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: 'Clear search',
                                  icon: const Icon(Icons.clear, size: 18),
                                  onPressed: () {
                                    _searchController.clear();
                                    ref
                                        .read(taskListControllerProvider.notifier)
                                        .setSearchQuery('');
                                  },
                                ),
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 8),
                PopupMenuButton<TaskSortBy>(
                  icon: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: theme.colorScheme.outlineVariant),
                    ),
                    child: const Icon(Icons.sort_rounded, size: 20),
                  ),
                  tooltip: 'Sort tasks',
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  onSelected: ref.read(taskListControllerProvider.notifier).setSortBy,
                  itemBuilder: (_) => [
                    _sortMenuItem(TaskSortBy.createdDate, 'Sort by created date', state.sortBy),
                    _sortMenuItem(TaskSortBy.dueDate, 'Sort by due date', state.sortBy),
                    _sortMenuItem(TaskSortBy.priority, 'Sort by priority', state.sortBy),
                  ],
                ),
              ],
            ),
          ),

          // Status filter chips.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
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

          Expanded(child: _buildBody(state, visibleTasks)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => TaskFormSheet.show(context),
        icon: const Icon(Icons.add),
        label: const Text('New Task'),
      ),
    );
  }

  Widget _buildBody(TaskListState state, List<TaskModel> visibleTasks) {
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

    return EmptyStateView(
      icon: Icons.task_alt_outlined,
      title: 'No tasks yet',
      description: 'Stay organized by adding your first task.',
      actionLabel: 'Create a Task',
      onAction: () => TaskFormSheet.show(context),
    );
  }

  PopupMenuItem<TaskSortBy> _sortMenuItem(TaskSortBy value, String label, TaskSortBy current) {
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
      onSelected: (_) => ref.read(taskListControllerProvider.notifier).setFilter(filter),
    );
  }
}
