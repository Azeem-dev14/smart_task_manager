import 'package:flutter_test/flutter_test.dart';
import 'package:smart_task_manager/core/database/app_database.dart';
import 'package:smart_task_manager/core/errors/app_exceptions.dart';
import 'package:smart_task_manager/features/tasks/domain/models/task_model.dart';
import 'package:smart_task_manager/features/tasks/presentation/controllers/task_list_controller.dart';

void main() {
  group('TaskModel & Drift Mapping Tests', () {
    test('TaskModel parses JSON and maps correctly to API payload', () {
      final now = DateTime.now();
      final task = TaskModel(
        id: 42,
        localId: 1,
        userId: 'test_user',
        title: 'Review PR for Clean Architecture',
        description: 'Ensure Riverpod DI is properly configured',
        isCompleted: false,
        dueDate: now.add(const Duration(days: 1)),
        priority: TaskPriority.high,
        category: TaskCategory.work,
        createdAt: now,
        updatedAt: now,
        syncStatus: SyncStatus.synced,
      );

      final json = task.toJson();
      expect(json['id'], 42);
      expect(json['title'], 'Review PR for Clean Architecture');
      expect(json['priority'], 'High');
      expect(json['category'], 'Work');

      final apiPayload = task.toApiCreateJson();
      expect(apiPayload.containsKey('id'), false); // Server assigns ID
      expect(apiPayload['title'], 'Review PR for Clean Architecture');
      expect(apiPayload['priority'], 'High');

      final fromJsonTask = TaskModel.fromJson(json);
      expect(fromJsonTask.id, task.id);
      expect(fromJsonTask.title, task.title);
      expect(fromJsonTask.priority, TaskPriority.high);
    });
  });

  group('Task Filtering, Search & Sorting Tests', () {
    final now = DateTime.now();
    final task1 = TaskModel(
      id: 1,
      userId: 'u1',
      title: 'Buy groceries',
      isCompleted: false,
      priority: TaskPriority.low,
      category: TaskCategory.shopping,
      createdAt: now.subtract(const Duration(hours: 2)),
      updatedAt: now.subtract(const Duration(hours: 2)),
      dueDate: now.add(const Duration(days: 3)),
    );

    final task2 = TaskModel(
      id: 2,
      userId: 'u1',
      title: 'Fix critical database bug',
      isCompleted: true,
      priority: TaskPriority.high,
      category: TaskCategory.work,
      createdAt: now.subtract(const Duration(hours: 1)),
      updatedAt: now.subtract(const Duration(hours: 1)),
      dueDate: now.add(const Duration(days: 1)),
    );

    final task3 = TaskModel(
      id: 3,
      userId: 'u1',
      title: 'Go for 5km running workout',
      isCompleted: false,
      priority: TaskPriority.medium,
      category: TaskCategory.health,
      createdAt: now,
      updatedAt: now,
      dueDate: now.add(const Duration(days: 2)),
    );

    final tasks = [task1, task2, task3];

    test('Filters pending tasks correctly', () {
      final state = TaskListState(
        allTasks: tasks,
        filter: TaskFilter.pending,
      );

      final visible = state.visibleTasks;
      expect(visible.length, 2);
      expect(visible.every((t) => !t.isCompleted), true);
    });

    test('Filters completed tasks correctly', () {
      final state = TaskListState(
        allTasks: tasks,
        filter: TaskFilter.completed,
      );

      final visible = state.visibleTasks;
      expect(visible.length, 1);
      expect(visible.first.title, 'Fix critical database bug');
    });

    test('Searches by title query (case-insensitive)', () {
      final state = TaskListState(
        allTasks: tasks,
        searchQuery: 'bug',
      );

      final visible = state.visibleTasks;
      expect(visible.length, 1);
      expect(visible.first.id, 2);
    });

    test('Sorts by priority (High -> Medium -> Low)', () {
      final state = TaskListState(
        allTasks: tasks,
        sortBy: TaskSortBy.priority,
      );

      final visible = state.visibleTasks;
      expect(visible.first.priority, TaskPriority.high);
      expect(visible[1].priority, TaskPriority.medium);
      expect(visible.last.priority, TaskPriority.low);
    });

    test('Sorts by due date ascending', () {
      final state = TaskListState(
        allTasks: tasks,
        sortBy: TaskSortBy.dueDate,
      );

      final visible = state.visibleTasks;
      expect(visible.first.id, 2); // 1 day
      expect(visible[1].id, 3); // 2 days
      expect(visible.last.id, 1); // 3 days
    });
  });

  group('AppException Error Hierarchy Tests', () {
    test('Maps Firebase error codes to human friendly messages', () {
      final authEx = AuthException.fromFirebaseCode('wrong-password');
      expect(authEx.message, 'Incorrect password. Please try again.');

      final emailEx = AuthException.fromFirebaseCode('email-already-in-use');
      expect(emailEx.message, 'An account already exists with this email.');
    });

    test('NetworkException and ServerException contain expected details', () {
      const netEx = NetworkException('No internet connection');
      expect(netEx.toString(), 'No internet connection');

      const serverEx = ServerException('Not found', statusCode: 404);
      expect(serverEx.statusCode, 404);
      expect(serverEx.message, 'Not found');
    });
  });
}
