import 'package:flutter/material.dart';

/// Reusable badge widget indicating whether a task is awaiting remote synchronization.
class SyncStatusBadge extends StatelessWidget {
  /// Whether the task has pending mutations.
  final bool isPendingSync;

  /// Constructs a [SyncStatusBadge].
  const SyncStatusBadge({super.key, required this.isPendingSync});

  @override
  Widget build(BuildContext context) {
    if (!isPendingSync) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.amber.shade900.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.amber.shade700.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_upload_outlined, size: 12, color: Colors.amber.shade800),
          const SizedBox(width: 4),
          Text(
            'Pending Sync',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.amber.shade800,
            ),
          ),
        ],
      ),
    );
  }
}
