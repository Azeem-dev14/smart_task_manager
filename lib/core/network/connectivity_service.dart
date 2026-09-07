import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Real-time network reachability and connectivity monitoring service.
///
/// Uses [Connectivity] to listen to hardware network state changes and broadcasts
/// boolean online/offline events across the application.
class ConnectivityService {
  final Connectivity _connectivity;
  final _controller = StreamController<bool>.broadcast();
  StreamSubscription<List<ConnectivityResult>>? _subscription;

  /// Last observed connectivity state, kept so callers can make a synchronous
  /// decision without paying for a platform channel round trip every time.
  bool _lastKnownOnline = true;

  /// Constructs the [ConnectivityService] and starts listening to connectivity changes.
  ConnectivityService({Connectivity? connectivity})
      : _connectivity = connectivity ?? Connectivity() {
    _init();
  }

  /// Most recently observed connectivity state.
  bool get lastKnownOnline => _lastKnownOnline;

  /// Broadcast stream emitting `true` when connectivity is present, `false` when offline.
  ///
  /// The stream replays the current state to every new subscriber before
  /// forwarding live transitions, so a listener attaching after startup (the
  /// offline banner, for instance) immediately renders the correct state.
  Stream<bool> get isOnlineStream async* {
    yield await checkConnection();
    yield* _controller.stream;
  }

  void _init() {
    _subscription = _connectivity.onConnectivityChanged.listen((results) {
      _lastKnownOnline = _isOnline(results);
      _controller.add(_lastKnownOnline);
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
      _lastKnownOnline = _isOnline(results);
    } catch (_) {
      // Platform channel unavailable (e.g. in tests): fall back to the last
      // value rather than falsely reporting the device as offline.
    }
    return _lastKnownOnline;
  }

  /// Closes the internal broadcast stream controller.
  void dispose() {
    _subscription?.cancel();
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
  return service.isOnlineStream.distinct();
});
