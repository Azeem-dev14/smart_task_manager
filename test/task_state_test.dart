import 'package:flutter_test/flutter_test.dart';
import 'package:smart_task_manager/core/errors/app_exceptions.dart';
import 'package:smart_task_manager/features/tasks/domain/models/task_filter.dart';
import 'package:smart_task_manager/features/tasks/domain/models/task_model.dart';
import 'package:smart_task_manager/features/tasks/domain/models/task_sort_by.dart';
import 'package:smart_task_manager/features/tasks/presentation/states/task_list_state.dart';

TaskModel _task({
  required int id,
  required String title,
  bool isCompleted = false,
  TaskPriority priority = TaskPriority.medium,
  DateTime? dueDate,
  DateTime? createdAt,
  String? description,
}) {
  final now = createdAt ?? DateTime(2026, 1, 1);
  return TaskModel(
    id: id,
    userId: 'u1',
    title: title,
    description: description,
    isCompleted: isCompleted,
    priority: priority,
    dueDate: dueDate,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  group('TaskModel.copyWith null handling', () {
    test('leaves the due date and description untouched when omitted', () {
      final original = _task(
        id: 1,
        title: 'Ship release build',
        description: 'Sign the APK',
        dueDate: DateTime(2026, 5, 1),
      );

      final renamed = original.copyWith(title: 'Ship the release build');

      expect(renamed.title, 'Ship the release build');
      expect(renamed.dueDate, DateTime(2026, 5, 1));
      expect(renamed.description, 'Sign the APK');
    });

    test('clears the due date only when explicitly asked', () {
      final original = _task(id: 1, title: 'Ship', dueDate: DateTime(2026, 5, 1));

      // Passing null alone must not be mistaken for "remove this value".
      expect(original.copyWith(dueDate: null).dueDate, DateTime(2026, 5, 1));
      expect(original.copyWith(clearDueDate: true).dueDate, isNull);
    });

    test('clears the description only when explicitly asked', () {
      final original = _task(id: 1, title: 'Ship', description: 'notes');

      expect(original.copyWith(description: null).description, 'notes');
      expect(original.copyWith(clearDescription: true).description, isNull);
    });
  });

  group('TaskListState.copyWith error handling', () {
    test('preserves an existing error across unrelated updates', () {
      const state = TaskListState(error: NetworkException('offline'));

      // Changing the filter must not silently discard a reported failure.
      final filtered = state.copyWith(filter: TaskFilter.completed);

      expect(filtered.error, isA<NetworkException>());
      expect(filtered.filter, TaskFilter.completed);
    });

    test('clears the error only through the explicit flag', () {
      const state = TaskListState(error: ServerException('boom', statusCode: 500));

      expect(state.copyWith(clearError: true).error, isNull);
    });
  });

  group('Filtering, search and sorting', () {
    final tasks = [
      _task(
        id: 1,
        title: 'Buy groceries',
        priority: TaskPriority.low,
        createdAt: DateTime(2026, 1, 1),
        dueDate: DateTime(2026, 3, 4),
      ),
      _task(
        id: 2,
        title: 'Fix critical database bug',
        isCompleted: true,
        priority: TaskPriority.high,
        createdAt: DateTime(2026, 1, 2),
        dueDate: DateTime(2026, 3, 2),
      ),
      _task(
        id: 3,
        title: 'Debug the sync engine',
        priority: TaskPriority.medium,
        createdAt: DateTime(2026, 1, 3),
      ),
    ];

    test('combines the status filter with the search query', () {
      final state = TaskListState(
        allTasks: tasks,
        filter: TaskFilter.pending,
        searchQuery: 'bug',
      );

      // "Fix critical database bug" matches the text but is completed.
      expect(state.visibleTasks.map((t) => t.id), [3]);
    });

    test('search is case-insensitive and trimmed', () {
      final state = TaskListState(allTasks: tasks, searchQuery: '  GROCERIES  ');
      expect(state.visibleTasks.single.id, 1);
    });

    test('sorts by priority, newest first inside a band', () {
      final state = TaskListState(allTasks: tasks, sortBy: TaskSortBy.priority);

      expect(
        state.visibleTasks.map((t) => t.priority),
        [TaskPriority.high, TaskPriority.medium, TaskPriority.low],
      );
    });

    test('sorts undated tasks last when sorting by due date', () {
      final state = TaskListState(allTasks: tasks, sortBy: TaskSortBy.dueDate);

      expect(state.visibleTasks.map((t) => t.id), [2, 1, 3]);
      expect(state.visibleTasks.last.dueDate, isNull);
    });

    test('sorts by created date, most recent first', () {
      final state = TaskListState(allTasks: tasks, sortBy: TaskSortBy.createdDate);
      expect(state.visibleTasks.map((t) => t.id), [3, 2, 1]);
    });

    test('reports whether the list is being narrowed', () {
      expect(const TaskListState().hasActiveQuery, isFalse);
      expect(const TaskListState(searchQuery: 'a').hasActiveQuery, isTrue);
      expect(const TaskListState(filter: TaskFilter.completed).hasActiveQuery, isTrue);
    });
  });

  group('TaskModel API contract', () {
    test('parses the backend task payload', () {
      final task = TaskModel.fromJson({
        'title': 'probe',
        'description': null,
        'is_completed': false,
        'due_date': null,
        'priority': 'High',
        'category': 'Work',
        'id': 449,
        'user_id': 'abc',
        'created_at': '2026-09-07T18:42:57',
        'updated_at': '2026-09-07T18:42:57',
      });

      expect(task.id, 449);
      expect(task.priority, TaskPriority.high);
      expect(task.category, TaskCategory.work);
      expect(task.isCompleted, isFalse);
    });

    test('create payload carries only fields the API accepts', () {
      final payload = _task(id: 1, title: 'probe').toApiCreateJson();

      expect(payload.keys, containsAll(<String>[
        'title',
        'description',
        'is_completed',
        'due_date',
        'priority',
        'category',
      ]));
      expect(payload.containsKey('id'), isFalse);
      expect(payload.containsKey('user_id'), isFalse);
    });

    test('unknown priority and category values fall back to defaults', () {
      expect(TaskPriority.fromString('urgent'), TaskPriority.medium);
      expect(TaskCategory.fromString(null), TaskCategory.work);
      expect(TaskCategory.fromString('personal'), TaskCategory.personal);
    });
  });
}
