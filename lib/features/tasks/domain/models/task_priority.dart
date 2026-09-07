enum TaskPriority {
  low('Low'),
  medium('Medium'),
  high('High');

  final String value;
  const TaskPriority(this.value);

  static TaskPriority fromString(String? val) {
    if (val == null) return TaskPriority.medium;
    return TaskPriority.values.firstWhere(
      (e) => e.value.toLowerCase() == val.toLowerCase(),
      orElse: () => TaskPriority.medium,
    );
  }
}
