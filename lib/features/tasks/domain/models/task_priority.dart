/// Task importance, matching the `Priority` enum exposed by the backend.
enum TaskPriority {
  /// Lowest importance.
  low('Low', 2),

  /// Default importance.
  medium('Medium', 1),

  /// Highest importance.
  high('High', 0);

  /// Wire value sent to and received from the API.
  final String value;

  /// Sort weight, ascending from the most important task.
  final int rank;

  const TaskPriority(this.value, this.rank);

  /// Parses an API priority string, defaulting to [TaskPriority.medium].
  static TaskPriority fromString(String? val) {
    if (val == null) return TaskPriority.medium;
    return TaskPriority.values.firstWhere(
      (e) => e.value.toLowerCase() == val.toLowerCase(),
      orElse: () => TaskPriority.medium,
    );
  }
}
