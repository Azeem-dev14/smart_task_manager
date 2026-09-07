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
  ApiClient({this.getUserId}) {
    dio = Dio(
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
      // Interceptor 1: Automatic user_id query parameter injection & error mapping
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
        onError: (DioException e, handler) {
          final mappedException = _mapDioException(e);
          handler.next(
            DioException(
              requestOptions: e.requestOptions,
              response: e.response,
              type: e.type,
              error: mappedException,
              message: mappedException.message,
            ),
          );
        },
      ),
      // Interceptor 2: Debug logging
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
          dev.log('<-- ERROR ${e.response?.statusCode} ${e.requestOptions.uri}: ${e.message}', name: 'API');
          handler.next(e);
        },
      ),
    ]);
  }

  /// Maps a raw [DioException] into the domain [AppException] hierarchy.
  static AppException _mapDioException(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.connectionError:
        return NetworkException(
          'Network connection timeout. Please check your internet connection.',
          'network-timeout',
          e,
        );

      case DioExceptionType.badResponse:
        final status = e.response?.statusCode;
        final data = e.response?.data;
        String message = 'Server error occurred ($status)';

        if (data is Map) {
          if (data.containsKey('detail')) {
            final detail = data['detail'];
            if (detail is String) {
              message = detail;
            } else if (detail is List && detail.isNotEmpty) {
              final first = detail.first;
              if (first is Map && first.containsKey('msg')) {
                message = first['msg'].toString();
              } else {
                message = detail.toString();
              }
            }
          } else if (data.containsKey('message')) {
            message = data['message'].toString();
          }
        }
        return ServerException(message, statusCode: status, originalError: e);

      case DioExceptionType.cancel:
        return const NetworkException('Request was cancelled.', 'request-cancelled');

      case DioExceptionType.badCertificate:
        return const NetworkException('Security certificate verification failed.', 'bad-certificate');

      case DioExceptionType.unknown:
      default:
        return NetworkException(
          e.message ?? 'An unexpected network error occurred.',
          'network-unknown',
          e,
        );
    }
  }
}

/// Riverpod provider for the singleton [ApiClient].
final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient();
});
