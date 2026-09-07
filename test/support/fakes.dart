import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';

/// Test doubles shared across the repository- and provider-level test
/// suites, so the backend/connectivity simulation lives in exactly one place.

/// Records a single request the app sent to the backend.
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
      return _json(
        {'status': 'error', 'message': 'Task not found', 'detail': 'Task not found'},
        404,
      );
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
      return _json(
        {'status': 'error', 'message': 'Task not found', 'detail': 'Task not found'},
        404,
      );
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
