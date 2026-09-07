/// Defines sync status constants for offline-first synchronization.
///
/// In an offline-first architecture, each local record tracks its
/// synchronization lifecycle state against the remote backend:
/// - [synced]: The record is in sync with the remote server.
/// - [pendingCreate]: Created while offline; needs to be pushed via POST.
/// - [pendingUpdate]: Modified while offline; needs to be pushed via PUT.
/// - [pendingDelete]: Deleted while offline; needs to be pushed via DELETE.
class SyncStatus {
  SyncStatus._();

  /// Record is fully synchronized with the remote API.
  static const String synced = 'synced';

  /// Record was created locally while offline and awaits remote creation.
  static const String pendingCreate = 'pending_create';

  /// Record was edited locally while offline and awaits remote update.
  static const String pendingUpdate = 'pending_update';

  /// Record was deleted locally while offline and awaits remote deletion.
  static const String pendingDelete = 'pending_delete';
}
