/// Global application-wide constants and configuration values.
class AppConstants {
  AppConstants._();

  /// Base URL of the remote FastAPI backend.
  static const String apiBaseUrl = 'https://taskmanager.uat-lplusltd.com';

  /// Connection timeout in milliseconds for HTTP network requests.
  static const int apiConnectTimeoutMs = 15000;

  /// Response receive timeout in milliseconds for HTTP network requests.
  static const int apiReceiveTimeoutMs = 15000;

  /// Default page size for paginated task queries (`skip` & `limit`).
  static const int defaultPageLimit = 10;

  /// Hive box name for application settings and user preferences.
  static const String settingsBoxName = 'settings_box';

  /// Storage key for persisting selected theme mode ('light', 'dark', 'system').
  static const String keyThemeMode = 'app_theme_mode';

  /// Storage key for cached user profile JSON.
  static const String keyCachedUser = 'cached_user_profile';

  /// Storage key for currently active user UID.
  static const String keyCachedUid = 'cached_user_uid';
}
