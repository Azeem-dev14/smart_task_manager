import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smart_task_manager/core/theme/text_styles.dart';
import 'package:smart_task_manager/core/widgets/empty_state_view.dart';
import 'package:smart_task_manager/features/tasks/presentation/controllers/task_list_notifier.dart';
import 'package:smart_task_manager/features/tasks/presentation/widgets/task_card.dart';

/// Full-page search over the task list, launched via [showSearch].
///
/// Filters entirely locally against the cached task list — it never writes
/// to the dashboard's shared `searchQuery` state. Flutter's search route can
/// be dismissed several ways (the leading arrow, a system back gesture, an
/// iOS swipe-back) and only some of those call [close]; coupling this page
/// to shared state left the dashboard filtered by a query no field on it
/// could show or clear once dismissed by a path that skipped [close].
class TaskSearchDelegate extends SearchDelegate<String?> {
  TaskSearchDelegate() : super(searchFieldLabel: 'Search tasks by title...');

  /// Matches the query text and hint to the same `bodyMedium` size used by
  /// the tappable search bar on the dashboard — the default search field
  /// otherwise renders noticeably larger (`titleLarge`).
  @override
  ThemeData appBarTheme(BuildContext context) {
    final base = super.appBarTheme(context);
    final bodyMedium = context.bodyMedium;

    return base.copyWith(
      textTheme: base.textTheme.copyWith(titleLarge: bodyMedium),
      inputDecorationTheme: base.inputDecorationTheme.copyWith(
        hintStyle: bodyMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
        ),
      ),
    );
  }

  @override
  List<Widget> buildActions(BuildContext context) {
    return [
      if (query.isNotEmpty)
        IconButton(
          tooltip: 'Clear search',
          icon: const Icon(Icons.clear),
          onPressed: () {
            query = '';
            showSuggestions(context);
          },
        ),
    ];
  }

  @override
  Widget buildLeading(BuildContext context) {
    return IconButton(
      tooltip: 'Back',
      icon: const Icon(Icons.arrow_back),
      onPressed: () => close(context, null),
    );
  }

  @override
  Widget buildResults(BuildContext context) => _SearchResultsView(query: query);

  @override
  Widget buildSuggestions(BuildContext context) => _SearchResultsView(query: query);
}

/// Debounces [query] locally and renders the matching tasks, entirely
/// independent of the dashboard's own filter/sort/search state.
class _SearchResultsView extends ConsumerStatefulWidget {
  final String query;

  const _SearchResultsView({required this.query});

  @override
  ConsumerState<_SearchResultsView> createState() => _SearchResultsViewState();
}

class _SearchResultsViewState extends ConsumerState<_SearchResultsView> {
  Timer? _debounce;
  late String _debouncedQuery = widget.query;

  @override
  void didUpdateWidget(covariant _SearchResultsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.query == widget.query) return;

    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _debouncedQuery = widget.query);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final trimmed = _debouncedQuery.trim();

    if (trimmed.isEmpty) {
      return const EmptyStateView(
        icon: Icons.search_rounded,
        title: 'Search your tasks',
        description: 'Start typing to find a task by its title.',
      );
    }

    // Search spans every cached task regardless of the dashboard's current
    // status filter, so a completed task is still findable while "Pending"
    // is selected there.
    final allTasks = ref.watch(taskListControllerProvider).allTasks;
    final lowerQuery = trimmed.toLowerCase();
    final results = allTasks.where((t) => t.title.toLowerCase().contains(lowerQuery)).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    if (results.isEmpty) {
      return EmptyStateView(
        icon: Icons.search_off_rounded,
        title: 'No results found',
        description: 'No tasks match "$trimmed".',
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Results - ${results.length}',
              style: context.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.only(top: 4, bottom: 24),
            itemCount: results.length,
            itemBuilder: (context, index) => TaskCard(task: results[index]),
          ),
        ),
      ],
    );
  }
}
