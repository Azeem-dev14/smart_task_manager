import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:smart_task_manager/core/constants/app_constants.dart';
import 'package:smart_task_manager/core/errors/app_exceptions.dart';

/// Local key-value storage service using [Hive] for application settings and user profile persistence.
class HiveService {
  late Box _tasksBox;
  late Box _syncQueueBox;
  late Box _settingsBox;

  /// Hive box for tasks fallback cache.
  Box get tasksBox => _tasksBox;

  /// Hive box for pending synchronization tasks queue.
  Box get syncQueueBox => _syncQueueBox;

  /// Hive box for user preferences and profile session cache.
  Box get settingsBox => _settingsBox;

  /// Initializes Hive for Flutter and opens required storage boxes.
  Future<void> init() async {
    try {
      await Hive.initFlutter();
      _tasksBox = await Hive.openBox(AppConstants.tasksBoxName);
      _syncQueueBox = await Hive.openBox(AppConstants.syncQueueBoxName);
      _settingsBox = await Hive.openBox(AppConstants.settingsBoxName);
    } catch (e) {
      throw CacheException('Failed to initialize local Hive storage: $e', originalError: e);
    }
  }

  // --- Tasks Cache Methods ---

  /// Retrieves all cached task JSON maps from Hive.
  List<Map<String, dynamic>> getCachedTasks() {
    try {
      final List<Map<String, dynamic>> list = [];
      for (final key in _tasksBox.keys) {
        final val = _tasksBox.get(key);
        if (val is Map) {
          list.add(Map<String, dynamic>.from(val));
        }
      }
      return list;
    } catch (e) {
      throw CacheException('Error reading cached tasks', originalError: e);
    }
  }

  /// Clears existing cached tasks and replaces them with [tasks].
  Future<void> saveCachedTasks(List<Map<String, dynamic>> tasks) async {
    try {
      final map = <dynamic, dynamic>{};
      for (final t in tasks) {
        final id = t['id'];
        if (id != null) {
          map[id.toString()] = t;
        }
      }
      await _tasksBox.clear();
      await _tasksBox.putAll(map);
    } catch (e) {
      throw CacheException('Error caching tasks to local storage', originalError: e);
    }
  }

  /// Inserts or updates an individual task entry in the Hive cache.
  Future<void> putCachedTask(Map<String, dynamic> task) async {
    try {
      final id = task['id'];
      if (id != null) {
        await _tasksBox.put(id.toString(), task);
      }
    } catch (e) {
      throw CacheException('Error saving task to local cache', originalError: e);
    }
  }

  /// Deletes a task entry from the Hive cache.
  Future<void> removeCachedTask(dynamic id) async {
    try {
      await _tasksBox.delete(id.toString());
    } catch (e) {
      throw CacheException('Error removing task from local cache', originalError: e);
    }
  }

  // --- Sync Queue Methods ---

  /// Reads all pending operations stored in the sync queue box.
  List<Map<String, dynamic>> getSyncQueue() {
    try {
      final List<Map<String, dynamic>> queue = [];
      for (final key in _syncQueueBox.keys) {
        final val = _syncQueueBox.get(key);
        if (val is Map) {
          queue.add(Map<String, dynamic>.from(val));
        }
      }
      return queue;
    } catch (e) {
      throw CacheException('Error reading offline sync queue', originalError: e);
    }
  }

  /// Adds a pending operation item to the sync queue.
  Future<void> addToSyncQueue(String queueKey, Map<String, dynamic> item) async {
    try {
      await _syncQueueBox.put(queueKey, item);
    } catch (e) {
      throw CacheException('Error adding item to sync queue', originalError: e);
    }
  }

  /// Removes an acknowledged operation item from the sync queue.
  Future<void> removeFromSyncQueue(String queueKey) async {
    try {
      await _syncQueueBox.delete(queueKey);
    } catch (e) {
      throw CacheException('Error removing item from sync queue', originalError: e);
    }
  }

  // --- Settings / Preferences ---

  /// Reads a preference setting by [key] with optional [defaultValue].
  dynamic getSetting(String key, {dynamic defaultValue}) {
    return _settingsBox.get(key, defaultValue: defaultValue);
  }

  /// Writes a preference setting [value] for [key].
  Future<void> putSetting(String key, dynamic value) async {
    try {
      await _settingsBox.put(key, value);
    } catch (e) {
      throw CacheException('Error writing setting to local storage', originalError: e);
    }
  }
}

/// Riverpod provider for [HiveService]. Must be overridden in root [ProviderScope].
final hiveServiceProvider = Provider<HiveService>((ref) {
  throw UnimplementedError('HiveService must be initialized and overridden in ProviderScope');
});
