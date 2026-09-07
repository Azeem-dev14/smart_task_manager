import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:smart_task_manager/core/constants/app_constants.dart';
import 'package:smart_task_manager/core/errors/app_exceptions.dart';

/// Local key-value storage service backed by [Hive].
///
/// Holds lightweight session state — the cached user profile and the persisted
/// theme preference. Task data deliberately lives in Drift/SQLite instead, which
/// is the single source of truth for the offline-first task cache.
class HiveService {
  late Box _settingsBox;

  /// Hive box for user preferences and profile session cache.
  Box get settingsBox => _settingsBox;

  /// Initializes Hive for Flutter and opens the settings box.
  ///
  /// [useFlutterInit] resolves the storage directory via a platform channel
  /// (`path_provider`), which only works with a real Flutter binding. Tests
  /// call [Hive.init] against a temp directory themselves beforehand and pass
  /// `false` here to just open the box on top of that.
  Future<void> init({bool useFlutterInit = true}) async {
    try {
      if (useFlutterInit) {
        await Hive.initFlutter();
      }
      _settingsBox = await Hive.openBox(AppConstants.settingsBoxName);
    } catch (e) {
      throw CacheException(
        'Failed to initialize local storage.',
        code: 'hive-init-failed',
        originalError: e,
      );
    }
  }

  /// Reads a preference setting by [key] with optional [defaultValue].
  dynamic getSetting(String key, {dynamic defaultValue}) {
    return _settingsBox.get(key, defaultValue: defaultValue);
  }

  /// Writes a preference setting [value] for [key].
  Future<void> putSetting(String key, dynamic value) async {
    try {
      await _settingsBox.put(key, value);
    } catch (e) {
      throw CacheException(
        'Could not save your preferences locally.',
        code: 'hive-write-failed',
        originalError: e,
      );
    }
  }

  /// Removes the stored value for [key].
  Future<void> removeSetting(String key) async {
    try {
      await _settingsBox.delete(key);
    } catch (e) {
      throw CacheException(
        'Could not clear local preferences.',
        code: 'hive-delete-failed',
        originalError: e,
      );
    }
  }
}

/// Riverpod provider for [HiveService]. Must be overridden in root [ProviderScope].
final hiveServiceProvider = Provider<HiveService>((ref) {
  throw UnimplementedError('HiveService must be initialized and overridden in ProviderScope');
});
