import 'dart:developer' as dev;
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smart_task_manager/core/constants/app_constants.dart';
import 'package:smart_task_manager/core/errors/app_exceptions.dart';

/// Function signature for retrieving the currently logged-in user's UID.
typedef CurrentUserIdGetter = String? Function();

/// HTTP REST API client built on [Dio].
///
/// Features custom interceptors for:
/// 1. Automatic `user_id` query parameter injection across all requests.
/// 2. Request & response logging.
/// 3. Standardized error mapping from [DioException] to [AppException] hierarchy.
class ApiClient {
  /// Internal configured [Dio] instance.
  late final Dio dio;

  /// Callback to retrieve the current user's UID for query parameter injection.
  final CurrentUserIdGetter? getUserId;

  /// Constructs an [ApiClient] and configures base options and interceptors.
  ApiClient({this.getUserId, Dio? dioOverride}) {
    dio = dioOverride ??
        Dio(
          BaseOptions(
            baseUrl: AppConstants.apiBaseUrl,
            connectTimeout: const Duration(milliseconds: AppConstants.apiConnectTimeoutMs),
            receiveTimeout: const Duration(milliseconds: AppConstants.apiReceiveTimeoutMs),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
          ),
        );

    dio.interceptors.addAll([
      // Interceptor 1: Automatic user_id query parameter injection.
      //
      // Every endpoint of the backend requires `user_id`, so callers never have
      // to remember it; an explicitly supplied value always wins.
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (!options.queryParameters.containsKey('user_id')) {
            final uid = getUserId?.call();
            if (uid != null && uid.isNotEmpty) {
              options.queryParameters['user_id'] = uid;
            }
          }
          handler.next(options);
        },
      ),

      // Interceptor 2: Debug logging of requests, responses and failures.
      InterceptorsWrapper(
        onRequest: (options, handler) {
          dev.log('--> ${options.method} ${options.uri}', name: 'API');
          if (options.data != null) {
            dev.log('Body: ${options.data}', name: 'API');
          }
          handler.next(options);
        },
        onResponse: (response, handler) {
          dev.log('<-- ${response.statusCode} ${response.requestOptions.uri}', name: 'API');
          handler.next(response);
        },
        onError: (DioException e, handler) {
          dev.log(
            '<-- ERROR ${e.response?.statusCode} ${e.requestOptions.uri}: ${e.message}',
            name: 'API',
          );
          handler.next(e);
        },
      ),

      // Interceptor 3: Error translation.
      //
      // Rejects with the domain [AppException] attached, so every caller can
      // recover a typed failure through [ApiClient.toAppException] instead of
      // reasoning about transport-level [DioException]s.
      InterceptorsWrapper(
        onError: (DioException e, handler) {
          handler.reject(
            DioException(
              requestOptions: e.requestOptions,
              response: e.response,
              type: e.type,
              error: mapDioException(e),
              message: e.message,
            ),
          );
        },
      ),
    ]);
  }

  /// Converts any thrown [error] into the domain [AppException] hierarchy.
  ///
  /// Unwraps the exception attached by the error interceptor, falling back to a
  /// fresh mapping (or [UnknownException]) so callers never leak transport types.
  static AppException toAppException(Object error) {
    if (error is AppException) return error;

    if (error is DioException) {
      final attached = error.error;
      if (attached is AppException) return attached;
      return mapDioException(error);
    }

    return UnknownException(error.toString(), 'unknown', error);
  }

  /// Maps a raw [DioException] into the domain [AppException] hierarchy.
  static AppException mapDioException(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
        return NetworkException(
          'The server is taking too long to respond. Please try again.',
          'network-timeout',
          e,
        );

      case DioExceptionType.connectionError:
        return NetworkException(
          'Unable to reach the server. Please check your internet connection.',
          'network-unreachable',
          e,
        );

      case DioExceptionType.badResponse:
        final status = e.response?.statusCode;
        return ServerException(
          _messageFromResponse(e.response?.data, status),
          statusCode: status,
          code: 'server-$status',
          originalError: e,
        );

      case DioExceptionType.cancel:
        return const NetworkException('Request was cancelled.', 'request-cancelled');

      case DioExceptionType.badCertificate:
        return const NetworkException(
          'Security certificate verification failed.',
          'bad-certificate',
        );

      case DioExceptionType.unknown:
        return NetworkException(
          e.message ?? 'An unexpected network error occurred.',
          'network-unknown',
          e,
        );
    }
  }

  /// Extracts a human readable message from a FastAPI error payload.
  ///
  /// Handles both the plain `{"detail": "..."}` shape and the validation error
  /// shape `{"detail": [{"loc": [...], "msg": "..."}]}`.
  static String _messageFromResponse(dynamic data, int? status) {
    if (data is Map) {
      final detail = data['detail'];
      if (detail is String && detail.isNotEmpty) return detail;
      if (detail is List && detail.isNotEmpty) {
        final first = detail.first;
        if (first is Map && first['msg'] != null) return first['msg'].toString();
        return detail.first.toString();
      }
      final message = data['message'];
      if (message is String && message.isNotEmpty) return message;
    }

    if (status != null && status >= 500) {
      return 'The server encountered an error ($status). Please try again later.';
    }
    return 'Request failed${status != null ? ' ($status)' : ''}. Please try again.';
  }
}

/// Riverpod provider for the singleton [ApiClient].
final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient();
});
