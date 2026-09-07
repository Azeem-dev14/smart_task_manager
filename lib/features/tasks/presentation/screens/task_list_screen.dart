import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smart_task_manager/core/widgets/empty_state_view.dart';
import 'package:smart_task_manager/core/widgets/error_view.dart';
import 'package:smart_task_manager/core/widgets/offline_banner.dart';
import 'package:smart_task_manager/features/auth/data/auth_repository.dart';
import 'package:smart_task_manager/features/profile/presentation/controllers/theme_controller.dart';
import 'package:smart_task_manager/features/profile/presentation/screens/profile_screen.dart';
import 'package:smart_task_manager/features/tasks/domain/models/task_filter.dart';
import 'package:smart_task_manager/features/tasks/domain/models/task_sort_by.dart';
import 'package:smart_task_manager/features/tasks/presentation/controllers/task_list_notifier.dart';
import 'package:smart_task_manager/features/tasks/presentation/widgets/task_card.dart';
import 'package:smart_task_manager/features/tasks/presentation/widgets/task_form_sheet.dart';

/// Primary dashboard screen displaying the task list with debounced search,
/// category/status filtering, sorting options, pull-to-refresh, and infinite scroll pagination.
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

  /// Infinite scroll listener: triggers page loading when scrolled within 200px of bottom.
  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
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
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
          ],
        ),
        actions: [
          // Theme Toggle
          IconButton(
            tooltip: isDark ? 'Switch to Light Mode' : 'Switch to Dark Mode',
            icon: Icon(isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
            onPressed: () => ref.read(themeControllerProvider.notifier).toggleTheme(),
          ),

          // Profile Navigation
          IconButton(
            tooltip: 'My Profile',
            icon: const Icon(Icons.account_circle_outlined),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ProfileScreen()),
              );
            },
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          // Real-time Offline Banner
          const OfflineBanner(),

          // Search and Sort Row
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Row(
              children: [
                // Debounced Search Field (300ms)
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    onChanged: (val) {
                      ref.read(taskListControllerProvider.notifier).setSearchQuery(val);
                    },
                    decoration: InputDecoration(
                      hintText: 'Search tasks by title...',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () {
                                _searchController.clear();
                                ref.read(taskListControllerProvider.notifier).setSearchQuery('');
                              },
                            )
                          : null,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // Sort Dropdown Menu
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
                  onSelected: (sort) {
                    ref.read(taskListControllerProvider.notifier).setSortBy(sort);
                  },
                  itemBuilder: (_) => [
                    _sortMenuItem(TaskSortBy.createdDate, 'Sort by Created Date', state.sortBy),
                    _sortMenuItem(TaskSortBy.dueDate, 'Sort by Due Date', state.sortBy),
                    _sortMenuItem(TaskSortBy.priority, 'Sort by Priority', state.sortBy),
                  ],
                ),
              ],
            ),
          ),

          // Filter Chips (All / Pending / Completed)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
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

          const Divider(height: 12),

          // Main Task List Content
          Expanded(
            child: Builder(
              builder: (context) {
                if (state.isLoading && state.allTasks.isEmpty) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (state.errorMessage != null && state.allTasks.isEmpty) {
                  return ErrorView(
                    error: state.errorMessage!,
                    onRetry: () => ref.read(taskListControllerProvider.notifier).refresh(),
                  );
                }

                if (visibleTasks.isEmpty) {
                  if (state.searchQuery.isNotEmpty) {
                    return EmptyStateView(
                      icon: Icons.search_off_rounded,
                      title: 'No results found',
                      description: 'No tasks matching "${state.searchQuery}"',
                    );
                  }

                  if (state.filter == TaskFilter.completed) {
                    return const EmptyStateView(
                      icon: Icons.check_circle_outline,
                      title: 'No completed tasks',
                      description: 'Mark tasks as done to see them here.',
                    );
                  }

                  return EmptyStateView(
                    icon: Icons.task_alt_outlined,
                    title: 'No tasks yet',
                    description: 'Stay organized by adding your tasks.',
                    actionLabel: 'Create a Task',
                    onAction: () => TaskFormSheet.show(context),
                  );
                }

                return RefreshIndicator(
                  onRefresh: () => ref.read(taskListControllerProvider.notifier).refresh(),
                  child: ListView.builder(
                    controller: _scrollController,
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.only(top: 4, bottom: 80),
                    itemCount: visibleTasks.length + (state.isLoadingMore ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == visibleTasks.length) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(16.0),
                            child: CircularProgressIndicator(),
                          ),
                        );
                      }

                      final task = visibleTasks[index];
                      return TaskCard(task: task);
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => TaskFormSheet.show(context),
        icon: const Icon(Icons.add),
        label: const Text('New Task'),
      ),
    );
  }

  PopupMenuItem<TaskSortBy> _sortMenuItem(TaskSortBy value, String label, TaskSortBy current) {
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          Icon(
            current == value ? Icons.radio_button_checked : Icons.radio_button_unchecked,
            size: 18,
            color: current == value ? Theme.of(context).colorScheme.primary : null,
          ),
          const SizedBox(width: 8),
          Text(label),
        ],
      ),
    );
  }

  Widget _filterChip(String label, TaskFilter filter, TaskFilter current) {
    final isSelected = current == filter;
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) {
        ref.read(taskListControllerProvider.notifier).setFilter(filter);
      },
    );
  }
}
