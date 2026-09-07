import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_task_manager/core/errors/app_exceptions.dart';
import 'package:smart_task_manager/core/network/api_client.dart';

RequestOptions _options() => RequestOptions(path: '/tasks/');

void main() {
  group('Dio to AppException mapping', () {
    test('connection failures map to NetworkException', () {
      final mapped = ApiClient.mapDioException(
        DioException(requestOptions: _options(), type: DioExceptionType.connectionError),
      );

      expect(mapped, isA<NetworkException>());
      expect(mapped.message, contains('internet connection'));
    });

    test('timeouts map to NetworkException', () {
      for (final type in [
        DioExceptionType.connectionTimeout,
        DioExceptionType.sendTimeout,
        DioExceptionType.receiveTimeout,
      ]) {
        final mapped = ApiClient.mapDioException(
          DioException(requestOptions: _options(), type: type),
        );
        expect(mapped, isA<NetworkException>(), reason: 'for $type');
      }
    });

    test('HTTP failures map to ServerException carrying the status code', () {
      final mapped = ApiClient.mapDioException(
        DioException(
          requestOptions: _options(),
          type: DioExceptionType.badResponse,
          response: Response(
            requestOptions: _options(),
            statusCode: 404,
            data: {'detail': 'Task not found'},
          ),
        ),
      );

      expect(mapped, isA<ServerException>());
      expect((mapped as ServerException).statusCode, 404);
      expect(mapped.message, 'Task not found');
    });

    test('FastAPI validation payloads surface the first field message', () {
      final mapped = ApiClient.mapDioException(
        DioException(
          requestOptions: _options(),
          type: DioExceptionType.badResponse,
          response: Response(
            requestOptions: _options(),
            statusCode: 422,
            data: {
              'detail': [
                {
                  'loc': ['body', 'title'],
                  'msg': 'Field required',
                  'type': 'missing',
                }
              ],
            },
          ),
        ),
      );

      expect(mapped, isA<ServerException>());
      expect(mapped.message, 'Field required');
    });

    test('server errors without a usable body still read sensibly', () {
      final mapped = ApiClient.mapDioException(
        DioException(
          requestOptions: _options(),
          type: DioExceptionType.badResponse,
          response: Response(requestOptions: _options(), statusCode: 500, data: '<html/>'),
        ),
      );

      expect(mapped, isA<ServerException>());
      expect(mapped.message, contains('500'));
    });
  });

  group('AppException recovery at the repository boundary', () {
    test('unwraps the typed exception attached by the error interceptor', () {
      const attached = ServerException('Task not found', statusCode: 404);

      final recovered = ApiClient.toAppException(
        DioException(requestOptions: _options(), error: attached),
      );

      expect(identical(recovered, attached), isTrue);
    });

    test('passes an AppException straight through', () {
      const original = CacheException('Local database unavailable');
      expect(identical(ApiClient.toAppException(original), original), isTrue);
    });

    test('falls back to UnknownException so the UI always gets a typed error', () {
      final recovered = ApiClient.toAppException(StateError('boom'));

      expect(recovered, isA<UnknownException>());
      expect(recovered, isA<AppException>());
    });
  });
}
