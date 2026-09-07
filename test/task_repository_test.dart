import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_task_manager/core/database/app_database.dart';
import 'package:smart_task_manager/core/errors/app_exceptions.dart';
import 'package:smart_task_manager/core/network/api_client.dart';
import 'package:smart_task_manager/core/network/connectivity_service.dart';
import 'package:smart_task_manager/features/tasks/data/task_repository.dart';
import 'package:smart_task_manager/features/tasks/domain/models/task_model.dart';

/// Records a single request the repository sent to the backend.
class RecordedCall {
  final String method;
  final String path;
  final Map<String, dynamic> query;
  final dynamic body;

  RecordedCall(this.method, this.path, this.query, this.body);

  @override
  String toString() => '$method $path $query';
}

/// Stubbed HTTP layer standing in for the Smart Task Manager API.
class FakeBackend implements HttpClientAdapter {
  final calls = <RecordedCall>[];

  /// Tasks the backend currently holds, keyed by server id.
  final Map<int, Map<String, dynamic>> tasks = {};

  /// When set, every request fails with this Dio error type.
  DioExceptionType? failWith;

  /// When set, requests respond with this HTTP status instead of succeeding.
  int? failStatus;

  int _nextId = 100;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    dynamic body;
    if (options.data is Map) body = options.data;

    calls.add(RecordedCall(options.method, options.path, options.queryParameters, body));

    if (failWith != null) {
      throw DioException(requestOptions: options, type: failWith!);
    }
    if (failStatus != null) {
      return _json({'status': 'error', 'message': 'nope', 'detail': 'nope'}, failStatus!);
    }

    switch (options.method) {
      case 'GET':
        return _listTasks(options);
      case 'POST':
        return _createTask(options);
      case 'PUT':
        return _updateTask(options);
      case 'DELETE':
        return _deleteTask(options);
    }
    return _json({'status': 'error', 'message': 'unsupported'}, 405);
  }

  ResponseBody _listTasks(RequestOptions options) {
    final skip = int.tryParse('${options.queryParameters['skip'] ?? 0}') ?? 0;
    final limit = int.tryParse('${options.queryParameters['limit'] ?? 10}') ?? 10;

    final ordered = tasks.keys.toList()..sort();
    final page = ordered.skip(skip).take(limit).map((id) => tasks[id]).toList();

    return _json({
      'status': 'success',
      'message': 'Tasks retrieved successfully',
      'data': page,
      'total': tasks.length,
    });
  }

  ResponseBody _createTask(RequestOptions options) {
    final payload = Map<String, dynamic>.from(options.data as Map);
    final id = _nextId++;
    final now = DateTime(2026, 2, 1).toIso8601String();

    tasks[id] = {
      ...payload,
      'id': id,
      'user_id': options.queryParameters['user_id'],
      'created_at': now,
      'updated_at': now,
    };

    return _json({'status': 'success', 'message': 'Task created', 'data': tasks[id]});
  }

  ResponseBody _updateTask(RequestOptions options) {
    final id = int.parse(options.path.split('/').last);
    if (!tasks.containsKey(id)) {
      return _json({'status': 'error', 'message': 'Task not found', 'detail': 'Task not found'}, 404);
    }

    tasks[id] = {
      ...tasks[id]!,
      ...Map<String, dynamic>.from(options.data as Map),
      'updated_at': DateTime(2026, 2, 2).toIso8601String(),
    };

    return _json({'status': 'success', 'message': 'Task updated', 'data': tasks[id]});
  }

  ResponseBody _deleteTask(RequestOptions options) {
    final id = int.parse(options.path.split('/').last);
    final removed = tasks.remove(id);
    if (removed == null) {
      return _json({'status': 'error', 'message': 'Task not found', 'detail': 'Task not found'}, 404);
    }
    return _json({'status': 'success', 'message': 'Task deleted', 'data': removed});
  }

  ResponseBody _json(Map<String, dynamic> payload, [int status = 200]) {
    return ResponseBody.fromString(
      jsonEncode(payload),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// Connectivity stub whose online state the test drives directly.
class FakeConnectivity implements Connectivity {
  final _controller = StreamController<List<ConnectivityResult>>.broadcast();
  List<ConnectivityResult> results;

  FakeConnectivity({bool online = true})
      : results = online ? [ConnectivityResult.wifi] : [ConnectivityResult.none];

  set online(bool value) {
    results = value ? [ConnectivityResult.wifi] : [ConnectivityResult.none];
    _controller.add(results);
  }

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => results;

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged => _controller.stream;
}

void main() {
  late AppDatabase db;
  late FakeBackend backend;
  late FakeConnectivity connectivity;
  late ConnectivityService connectivityService;
  late TaskRepository repository;

  const userId = 'user-1';

  setUp(() {
    db = AppDatabase.withExecutor(NativeDatabase.memory());
    backend = FakeBackend();
    connectivity = FakeConnectivity();
    connectivityService = ConnectivityService(connectivity: connectivity);

    final dio = Dio(BaseOptions(baseUrl: 'https://taskmanager.test'))
      ..httpClientAdapter = backend;

    repository = TaskRepository(
      apiClient: ApiClient(dioOverride: dio),
      db: db,
      connectivityService: connectivityService,
    );
  });

  tearDown(() async {
    connectivityService.dispose();
    await db.close();
  });

  Future<List<TaskModel>> localTasks() => repository.getLocalTasks(userId);

  group('Creating tasks', () {
    test('online creation reaches the backend and is marked synced', () async {
      await repository.createTask(userId: userId, title: 'Write the report');

      final stored = await localTasks();
      expect(stored, hasLength(1));
      expect(stored.single.isPendingSync, isFalse);
      expect(stored.single.syncStatus, SyncStatus.synced);
      // The local row now carries the identifier assigned by the backend.
      expect(stored.single.id, 100);

      expect(backend.calls.map((c) => c.method), ['POST']);
      expect(backend.calls.single.query['user_id'], userId);
    });

    test('offline creation is queued locally without any network call', () async {
      connectivity.online = false;

      await repository.createTask(userId: userId, title: 'Draft offline');

      final stored = await localTasks();
      expect(stored.single.syncStatus, SyncStatus.pendingCreate);
      expect(stored.single.isPendingSync, isTrue);
      expect(backend.calls, isEmpty);
      expect(backend.tasks, isEmpty);
    });

    test('a create that fails mid-flight stays queued rather than looking synced', () async {
      backend.failWith = DioExceptionType.connectionError;

      await repository.createTask(userId: userId, title: 'Flaky network');

      final stored = await localTasks();
      expect(stored.single.syncStatus, SyncStatus.pendingCreate);
      expect(stored.single.isPendingSync, isTrue);
    });
  });

  group('Sync engine', () {
    test('pushes everything queued while offline once connectivity returns', () async {
      connectivity.online = false;
      await repository.createTask(userId: userId, title: 'Queued one');
      await repository.createTask(userId: userId, title: 'Queued two');
      expect(backend.tasks, isEmpty);

      connectivity.online = true;
      await repository.pushPendingChanges(userId);

      expect(backend.tasks, hasLength(2));
      final stored = await localTasks();
      expect(stored.every((t) => t.syncStatus == SyncStatus.synced), isTrue);
      expect(stored.every((t) => !t.isPendingSync), isTrue);
    });

    test('an offline edit is pushed as an update, not a duplicate create', () async {
      await repository.createTask(userId: userId, title: 'Original');
      final created = (await localTasks()).single;

      connectivity.online = false;
      await repository.updateTask(
        userId: userId,
        task: created.copyWith(title: 'Renamed offline'),
      );
      expect((await localTasks()).single.syncStatus, SyncStatus.pendingUpdate);

      connectivity.online = true;
      await repository.pushPendingChanges(userId);

      expect(backend.tasks, hasLength(1));
      expect(backend.tasks.values.single['title'], 'Renamed offline');
      expect(backend.calls.where((c) => c.method == 'POST'), hasLength(1));
    });

    test('an offline delete leaves a tombstone that is flushed on reconnect', () async {
      await repository.createTask(userId: userId, title: 'Doomed');
      final created = (await localTasks()).single;

      connectivity.online = false;
      await repository.deleteTask(userId: userId, task: created);

      // Hidden from the UI immediately, but still tracked for the backend.
      expect(await localTasks(), isEmpty);
      expect(backend.tasks, hasLength(1));

      connectivity.online = true;
      await repository.pushPendingChanges(userId);

      expect(backend.tasks, isEmpty);
      final remaining = await db.getPendingSyncTasks(userId);
      expect(remaining, isEmpty);
    });

    test('deleting a task that never reached the server needs no request', () async {
      connectivity.online = false;
      await repository.createTask(userId: userId, title: 'Never synced');
      final created = (await localTasks()).single;

      await repository.deleteTask(userId: userId, task: created);

      expect(await localTasks(), isEmpty);
      expect(await db.getPendingSyncTasks(userId), isEmpty);
      expect(backend.calls, isEmpty);
    });

    test('toggling completion mirrors the new value to the backend', () async {
      await repository.createTask(userId: userId, title: 'Toggle me');
      final created = (await localTasks()).single;

      await repository.toggleCompletion(userId: userId, task: created);

      expect((await localTasks()).single.isCompleted, isTrue);
      expect(backend.tasks.values.single['is_completed'], true);
    });
  });

  group('Pagination', () {
    setUp(() {
      for (var i = 0; i < 25; i++) {
        backend.tasks[i + 1] = {
          'id': i + 1,
          'user_id': userId,
          'title': 'Server task ${i + 1}',
          'description': null,
          'is_completed': false,
          'due_date': null,
          'priority': 'Medium',
          'category': 'Work',
          'created_at': DateTime(2026, 1, 1).toIso8601String(),
          'updated_at': DateTime(2026, 1, 1).toIso8601String(),
        };
      }
    });

    test('pulls one page at a time and reports the true total', () async {
      final first = await repository.pullPage(userId: userId, skip: 0, limit: 10);

      expect(first.fetched, 10);
      expect(first.total, 25);
      expect(await localTasks(), hasLength(10));

      final second = await repository.pullPage(userId: userId, skip: 10, limit: 10);

      expect(second.fetched, 10);
      // Skip/limit advanced, so the second page holds different records.
      expect(await localTasks(), hasLength(20));
      expect(second.serverIds.intersection(first.serverIds), isEmpty);
    });

    test('the last page is short and adds no duplicates', () async {
      await repository.pullPage(userId: userId, skip: 0, limit: 10);
      await repository.pullPage(userId: userId, skip: 10, limit: 10);
      final last = await repository.pullPage(userId: userId, skip: 20, limit: 10);

      expect(last.fetched, 5);
      expect(await localTasks(), hasLength(25));
    });

    test('re-pulling the same page is idempotent', () async {
      await repository.pullPage(userId: userId, skip: 0, limit: 10);
      await repository.pullPage(userId: userId, skip: 0, limit: 10);

      expect(await localTasks(), hasLength(10));
    });

    test('the pagination cursor ignores tasks created offline', () async {
      // A locally created task must not shift the server-side `skip` window,
      // which is why the cursor counts fetched records rather than local rows.
      connectivity.online = false;
      await repository.createTask(userId: userId, title: 'Local only');
      connectivity.online = true;

      final first = await repository.pullPage(userId: userId, skip: 0, limit: 10);
      expect(first.fetched, 10);
      expect(await localTasks(), hasLength(11));

      final second = await repository.pullPage(userId: userId, skip: first.fetched, limit: 10);
      expect(second.serverIds.intersection(first.serverIds), isEmpty);
    });
  });

  group('Refreshing', () {
    test('re-pulls every page the user has already seen', () async {
      for (var i = 1; i <= 15; i++) {
        backend.tasks[i] = {
          'id': i,
          'user_id': userId,
          'title': 'Task $i',
          'is_completed': false,
          'priority': 'Medium',
          'category': 'Work',
          'created_at': DateTime(2026, 1, 1).toIso8601String(),
          'updated_at': DateTime(2026, 1, 1).toIso8601String(),
        };
      }

      final result = await repository.refreshTasks(userId: userId, minimumItems: 15);

      expect(result.fetched, 15);
      expect(result.total, 15);
      expect(await localTasks(), hasLength(15));
    });

    test('drops tasks that were deleted on another device', () async {
      backend.tasks[1] = {
        'id': 1,
        'user_id': userId,
        'title': 'Still there',
        'is_completed': false,
        'priority': 'Medium',
        'category': 'Work',
        'created_at': DateTime(2026, 1, 1).toIso8601String(),
        'updated_at': DateTime(2026, 1, 1).toIso8601String(),
      };
      backend.tasks[2] = {
        'id': 2,
        'user_id': userId,
        'title': 'Removed elsewhere',
        'is_completed': false,
        'priority': 'Medium',
        'category': 'Work',
        'created_at': DateTime(2026, 1, 1).toIso8601String(),
        'updated_at': DateTime(2026, 1, 1).toIso8601String(),
      };

      await repository.refreshTasks(userId: userId);
      expect(await localTasks(), hasLength(2));

      backend.tasks.remove(2);
      await repository.refreshTasks(userId: userId);

      final remaining = await localTasks();
      expect(remaining, hasLength(1));
      expect(remaining.single.title, 'Still there');
    });

    test('never prunes work that has not been pushed yet', () async {
      connectivity.online = false;
      await repository.createTask(userId: userId, title: 'Unsynced draft');
      connectivity.online = true;

      // The backend has nothing, so a naive prune would wipe the local draft.
      await repository.refreshTasks(userId: userId);

      final stored = await localTasks();
      expect(stored.map((t) => t.title), contains('Unsynced draft'));
    });
  });

  group('Failure handling', () {
    test('a lost connection surfaces as a NetworkException', () async {
      backend.failWith = DioExceptionType.connectionError;

      expect(
        () => repository.pullPage(userId: userId, skip: 0, limit: 10),
        throwsA(isA<NetworkException>()),
      );
    });

    test('a backend error surfaces as a ServerException with its status', () async {
      backend.failStatus = 500;

      await expectLater(
        repository.pullPage(userId: userId, skip: 0, limit: 10),
        throwsA(
          isA<ServerException>().having((e) => e.statusCode, 'statusCode', 500),
        ),
      );
    });

    test('cached tasks stay readable when the backend is unreachable', () async {
      await repository.createTask(userId: userId, title: 'Cached');
      backend.failWith = DioExceptionType.connectionError;

      // The offline-first contract: local reads never depend on the network.
      expect(await localTasks(), hasLength(1));
    });

    test('a task deleted remotely is cleaned up locally on the next push', () async {
      await repository.createTask(userId: userId, title: 'Gone remotely');
      final created = (await localTasks()).single;

      backend.tasks.clear();

      connectivity.online = false;
      await repository.updateTask(userId: userId, task: created.copyWith(title: 'Edit'));
      connectivity.online = true;

      await repository.pushPendingChanges(userId);

      expect(await localTasks(), isEmpty);
    });
  });

  group('Reactive stream', () {
    test('emits local writes immediately for optimistic UI updates', () async {
      final emissions = <List<TaskModel>>[];
      final subscription = repository.watchTasks(userId).listen(emissions.add);

      await repository.createTask(userId: userId, title: 'Optimistic');
      await pumpEventQueue();

      expect(emissions.last.single.title, 'Optimistic');
      await subscription.cancel();
    });

    test('excludes tasks pending deletion', () async {
      await repository.createTask(userId: userId, title: 'To delete');
      final created = (await localTasks()).single;

      connectivity.online = false;
      await repository.deleteTask(userId: userId, task: created);

      final visible = await repository.watchTasks(userId).first;
      expect(visible, isEmpty);
    });
  });
}
