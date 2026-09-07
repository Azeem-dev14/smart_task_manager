import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Real-time network reachability and connectivity monitoring service.
///
/// Uses [Connectivity] to listen to hardware network state changes and broadcasts
/// boolean online/offline events across the application.
class ConnectivityService {
  final Connectivity _connectivity = Connectivity();
  final _controller = StreamController<bool>.broadcast();

  /// Constructs the [ConnectivityService] and starts listening to connectivity changes.
  ConnectivityService() {
    _init();
  }

  /// Broadcast stream emitting `true` when network connectivity is present and `false` when offline.
  Stream<bool> get isOnlineStream => _controller.stream;

  void _init() {
    _connectivity.onConnectivityChanged.listen((results) {
      _controller.add(_isOnline(results));
    });
  }

  /// Evaluates whether any active connectivity result represents an online interface.
  bool _isOnline(List<ConnectivityResult> results) {
    if (results.isEmpty) return false;
    return results.any((r) => r != ConnectivityResult.none);
  }

  /// One-time snapshot check verifying active network connectivity.
  Future<bool> checkConnection() async {
    try {
      final results = await _connectivity.checkConnectivity();
      return _isOnline(results);
    } catch (_) {
      return false;
    }
  }

  /// Closes the internal broadcast stream controller.
  void dispose() {
    _controller.close();
  }
}

/// Provider supplying the application's singleton [ConnectivityService].
final connectivityServiceProvider = Provider<ConnectivityService>((ref) {
  final service = ConnectivityService();
  ref.onDispose(service.dispose);
  return service;
});

/// Reactive stream provider emitting whether the device is currently online.
final isOnlineProvider = StreamProvider<bool>((ref) {
  final service = ref.watch(connectivityServiceProvider);
  return service.isOnlineStream;
});
